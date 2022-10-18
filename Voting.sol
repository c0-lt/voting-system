// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract Voting is Ownable {
    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    uint256 private proposalCounter;
    uint256 private winningProposalId; // private -> accessible with getWinner
    address[] private votersAddresses; 
    mapping(address => Voter) public whitelist;
    mapping(uint256 => Proposal) public proposals; // id => prop 
    WorkflowStatus public votingStatus; // 0 by default -> RegisteringVoters

    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(
        WorkflowStatus previousStatus,
        WorkflowStatus newStatus
    );
    event ProposalRegistered(uint256 proposalId);
    event Voted(address voter, uint256 proposalId);
    event Equality(string log);
    event WinningProposal(string proposal);

    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint256 votedProposalId;
    }
    struct Proposal {
        string description;
        uint256 voteCount;
    }

    // Check if a function can be executed with current workflow status
    modifier isCurrentStatusCompatible(WorkflowStatus requiredStatus) {
        require(
            votingStatus == requiredStatus,
            "Forbidden action in current workflow status."
        );
        _;
    }

    modifier isVoter() {
        require(
            whitelist[msg.sender].isRegistered == true,
            "You are not a registered voter. Contact administrator."
        );
        _;
    }

    function registerVoter(address _address)
        public
        onlyOwner
        isCurrentStatusCompatible(WorkflowStatus.RegisteringVoters)
    {
        require(_address != address(0), "Voter address can't be 0x0.");
        require(
            !whitelist[_address].isRegistered,
            "This voter is already registered."
        );
        whitelist[_address] = Voter(true, false, 0);
        votersAddresses.push(_address);
        emit VoterRegistered(_address);
    }

    function registerProposal(string memory _description)
        public
        isVoter
        isCurrentStatusCompatible(WorkflowStatus.ProposalsRegistrationStarted)
    {
        require(
            bytes(_description).length > 0,
            "The proposal description can't be empty."
        );
        require(
            !isProposalExisting(_description),
            "Proposal already existing."
        );
        proposalCounter++;
        proposals[proposalCounter] = (Proposal(_description, 0));
        emit ProposalRegistered(proposalCounter);
    }

    function vote(uint256 _proposalId)
        public
        isVoter
        isCurrentStatusCompatible(WorkflowStatus.VotingSessionStarted)
    {
        require(!whitelist[msg.sender].hasVoted, "Voter can only vote once.");
        require(
            bytes(proposals[_proposalId].description).length > 0,
            "Proposal ID not found."
        );
        proposals[_proposalId].voteCount++;
        whitelist[msg.sender].hasVoted = true;
        whitelist[msg.sender].votedProposalId = _proposalId;
        emit Voted(msg.sender, _proposalId);
    }

    function setWinner() internal onlyOwner {
        uint256[] memory results = new uint256[](proposalCounter);
        
        // Push all voteCount into results array
        for (uint256 i = 1; i <= proposalCounter; i++) {
            results[i-1] = (proposals[i].voteCount);
        }
        uint256 maxVoteCount = getMaxInArray(results);
        
        if (isDuplicated(maxVoteCount, results)) {
            // If we have more than one max value inside results, it means
            // we have a vote equality, so we go back to VotingSessionStarted
            // after resetting votes, so that voters can reach consensus
            resetVotes();
            emit Equality("Equality during voting. Reopening vote.");
            startVoting();
        } else {
            uint256 index = getIndexInArray(maxVoteCount, results);
            winningProposalId = index + 1;
            emit WinningProposal(proposals[winningProposalId].description);
        }
    }

    function getWinner() public view returns (uint) {
        require(
            votingStatus == WorkflowStatus.VotesTallied,
            "Votes have not been tallied yet."
        );
        return winningProposalId;
    }

    // Make sure every voters voted
    function isVotingSessionCompleted() internal view returns (bool) {
        for (uint256 i; i < votersAddresses.length; i++) {
            if (!whitelist[votersAddresses[i]].hasVoted) {
                return false;
            }
        }
        return true;
    }

    function isProposalExisting(string memory _proposal)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 1; i <= proposalCounter; i++) {
            if (stringsEquals(_proposal, proposals[i].description)) {
                return true;
            }
        }
        return false;
    }

    function stringsEquals(string memory _string1, string memory _string2)
        private
        pure
        returns (bool)
    {
        bool equals;
        if (
            keccak256(abi.encodePacked(_string1)) ==
            keccak256(abi.encodePacked(_string2))
        ) {
            equals = true;
        }
        return equals;
    }

    function getMaxInArray(uint256[] memory _array) internal pure returns (uint256) {
        uint256 max;
        for (uint256 i; i < _array.length; i++) {
            if (_array[i] > max)
                max = _array[i];
        }
        return max;
    }

    function getIndexInArray(uint256 _element, uint256[] memory _array)
        internal
        pure
        returns (uint256) 
    {
        for (uint256 i; i < _array.length; i++) {
            if (_array[i] == _element)
                return i; 
        }
        return 0; // Ideally should return -1 if _element is not found 
    } 

    // Check for multiple _val in _array
    function isDuplicated(uint256 _val, uint256[] memory _array)
        internal
        pure
        returns (bool)
    {
        uint256 counter;
        for (uint256 i; i < _array.length; i++) {
            if (_array[i] == _val)
                counter++;
            if (counter > 1)
                return true;
        }
        return false;
    }

    function resetVotes() internal onlyOwner {
        for (uint256 i; i < votersAddresses.length; i++){
            whitelist[votersAddresses[i]].hasVoted = false;
            whitelist[votersAddresses[i]].votedProposalId = 0;
        } 
        for (uint256 j=1; j <= proposalCounter; j++){
            proposals[j].voteCount = 0;
        }
        winningProposalId = 0;
    }

    function changeWorkflowStatus(WorkflowStatus _newWorkflowStatus)
        internal
        onlyOwner
    {
        require(
            uint256(votingStatus) != uint256(_newWorkflowStatus),
            "Workflow already in this status."
        );
        //Check that we can't skip a status during workflow unless we reset voting session at the end
        // or there is an equality that requires to go back from VotingSessionEnded to VotingSessionStarted
        // so that voters can vote again until majority is reached
        require(
            (uint256(votingStatus) + 1 == uint256(_newWorkflowStatus)) ||
                (uint256(votingStatus) == 4 &&
                    uint256(_newWorkflowStatus) == 3) ||
                (uint256(votingStatus) - uint256(_newWorkflowStatus)) == 5,
            "Violation of workflow steps."
        );

        WorkflowStatus previousStatus = votingStatus;
        votingStatus = _newWorkflowStatus;
        emit WorkflowStatusChange(previousStatus, _newWorkflowStatus);
    }

    /* -- CHANGE WORKFLOW STATUS FUNCTIONS -- */
    function startVotersRegistration() public onlyOwner {
        changeWorkflowStatus(WorkflowStatus.RegisteringVoters);
    }

    function startProposalRegistration() public onlyOwner {
        require(
            votersAddresses.length >= 2,
            "Total number of voters must be at least 2."
        );
        changeWorkflowStatus(WorkflowStatus.ProposalsRegistrationStarted);
    }

    function endProposalRegistration() public onlyOwner {
        require(
            proposalCounter > 0,
            "At least one proposal is required to end proposal registration."
        );
        changeWorkflowStatus(WorkflowStatus.ProposalsRegistrationEnded);
    }

    function startVoting() public onlyOwner {
        changeWorkflowStatus(WorkflowStatus.VotingSessionStarted);
    }

    function endVoting() public onlyOwner {
        require(
            isVotingSessionCompleted(),
            "All voters must vote to end voting session."
        );
        changeWorkflowStatus(WorkflowStatus.VotingSessionEnded);
        setWinner();
    }

    function votesTallied() public onlyOwner {
        require(winningProposalId != 0, "Votes need to be tallied.");
        changeWorkflowStatus(WorkflowStatus.VotesTallied);
    }

    /* --- CHANGE WORKFLOW STATUS FUNCTIONS --- */

    receive() external payable {
        //Who knows ?! it's almost Christmas ...
    }
}
