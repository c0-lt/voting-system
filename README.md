# First project : Voting system
## Assumptions
- The admin is the only one that can move the workflow forward
- No step of the workflow can be skipped
- In case of vote equality, the workflow goes back from VotingSessionEnded to the VotingSessionStarted after having resetting the votes. It will loop on those status until a unique proposal is choosen.