// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title GovernanceMessaging
 * @dev DAO governance with proposal messaging and voting mechanisms
 * @author Swift v2 Team
 */
contract GovernanceMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    enum ProposalStatus { PENDING, ACTIVE, PASSED, REJECTED, EXECUTED }
    enum VoteType { AGAINST, FOR, ABSTAIN }

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        uint256 votingEndTime,
        uint256 timestamp
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        VoteType voteType,
        uint256 votingPower,
        uint256 timestamp
    );

    event ProposalExecuted(
        uint256 indexed proposalId,
        uint256 timestamp
    );

    // Structs
    struct Proposal {
        uint256 id;
        address proposer;
        string title;
        string description;
        string[] options;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 createdAt;
        uint256 votingStartTime;
        uint256 votingEndTime;
        ProposalStatus status;
        mapping(address => bool) hasVoted;
        mapping(address => VoteType) voterChoice;
        address[] voters;
    }

    // State variables
    Counters.Counter private _proposalIdCounter;
    mapping(uint256 => Proposal) public proposals;
    mapping(address => uint256[]) public userProposals;
    mapping(address => uint256) public votingPower; // User's voting weight

    // Constants
    uint256 public constant MIN_VOTING_PERIOD = 86400; // 1 day
    uint256 public constant MAX_VOTING_PERIOD = 604800; // 7 days
    uint256 public constant PROPOSAL_THRESHOLD = 1; // Min voting power to propose
    uint256 public constant QUORUM_PERCENTAGE = 10; // 10% quorum
    uint256 public constant PROPOSAL_FEE = 0.00001 ether;

    uint256 public totalVotingPower;

    constructor() {
        _proposalIdCounter.increment();
    }

    /**
     * @dev Set voting power for user (only owner)
     */
    function setVotingPower(address _user, uint256 _power) external onlyOwner {
        uint256 oldPower = votingPower[_user];
        votingPower[_user] = _power;
        
        // Update total
        if (_power > oldPower) {
            totalVotingPower += (_power - oldPower);
        } else {
            totalVotingPower -= (oldPower - _power);
        }
    }

    /**
     * @dev Create governance proposal
     * @param _title Proposal title
     * @param _description Detailed description
     * @param _votingDuration Duration in seconds
     */
    function createProposal(
        string memory _title,
        string memory _description,
        uint256 _votingDuration
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= PROPOSAL_FEE, "Insufficient fee");
        require(votingPower[msg.sender] >= PROPOSAL_THRESHOLD, "Insufficient voting power");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(_votingDuration >= MIN_VOTING_PERIOD, "Voting period too short");
        require(_votingDuration <= MAX_VOTING_PERIOD, "Voting period too long");
        
        uint256 proposalId = _proposalIdCounter.current();
        _proposalIdCounter.increment();

        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.title = _title;
        proposal.description = _description;
        proposal.createdAt = block.timestamp;
        proposal.votingStartTime = block.timestamp;
        proposal.votingEndTime = block.timestamp + _votingDuration;
        proposal.status = ProposalStatus.ACTIVE;
        proposal.forVotes = 0;
        proposal.againstVotes = 0;
        proposal.abstainVotes = 0;

        userProposals[msg.sender].push(proposalId);

        emit ProposalCreated(
            proposalId,
            msg.sender,
            _title,
            proposal.votingEndTime,
            block.timestamp
        );
    }

    /**
     * @dev Cast vote on proposal
     * @param _proposalId ID of the proposal
     * @param _voteType Vote type (AGAINST, FOR, ABSTAIN)
     */
    function castVote(uint256 _proposalId, VoteType _voteType) 
        external 
        nonReentrant 
    {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status == ProposalStatus.ACTIVE, "Proposal not active");
        require(block.timestamp >= proposal.votingStartTime, "Voting not started");
        require(block.timestamp < proposal.votingEndTime, "Voting ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(votingPower[msg.sender] > 0, "No voting power");

        uint256 weight = votingPower[msg.sender];

        proposal.hasVoted[msg.sender] = true;
        proposal.voterChoice[msg.sender] = _voteType;
        proposal.voters.push(msg.sender);

        if (_voteType == VoteType.FOR) {
            proposal.forVotes += weight;
        } else if (_voteType == VoteType.AGAINST) {
            proposal.againstVotes += weight;
        } else {
            proposal.abstainVotes += weight;
        }

        emit VoteCast(_proposalId, msg.sender, _voteType, weight, block.timestamp);
    }

    /**
     * @dev Finalize proposal after voting ends
     * @param _proposalId ID of the proposal
     */
    function finalizeProposal(uint256 _proposalId) 
        external 
        nonReentrant 
    {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status == ProposalStatus.ACTIVE, "Proposal not active");
        require(block.timestamp >= proposal.votingEndTime, "Voting not ended");

        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        uint256 quorum = (totalVotingPower * QUORUM_PERCENTAGE) / 100;

        // Check quorum
        if (totalVotes >= quorum && proposal.forVotes > proposal.againstVotes) {
            proposal.status = ProposalStatus.PASSED;
        } else {
            proposal.status = ProposalStatus.REJECTED;
        }
    }

    /**
     * @dev Execute passed proposal
     * @param _proposalId ID of the proposal
     */
    function executeProposal(uint256 _proposalId) 
        external 
        nonReentrant 
    {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status == ProposalStatus.PASSED, "Proposal not passed");

        proposal.status = ProposalStatus.EXECUTED;

        emit ProposalExecuted(_proposalId, block.timestamp);
    }

    /**
     * @dev Get proposal details
     */
    function getProposal(uint256 _proposalId) 
        external 
        view 
        returns (
            uint256 id,
            address proposer,
            string memory title,
            string memory description,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes,
            uint256 votingEndTime,
            ProposalStatus status
        )
    {
        Proposal storage proposal = proposals[_proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.title,
            proposal.description,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.abstainVotes,
            proposal.votingEndTime,
            proposal.status
        );
    }

    /**
     * @dev Get user's vote on proposal
     */
    function getUserVote(uint256 _proposalId, address _user) 
        external 
        view 
        returns (bool hasVoted, VoteType voteType)
    {
        Proposal storage proposal = proposals[_proposalId];
        return (proposal.hasVoted[_user], proposal.voterChoice[_user]);
    }

    /**
     * @dev Get user's proposals
     */
    function getUserProposals(address _user) external view returns (uint256[] memory) {
        return userProposals[_user];
    }

    /**
     * @dev Get user's voting power
     */
    function getUserVotingPower(address _user) external view returns (uint256) {
        return votingPower[_user];
    }

    /**
     * @dev Withdraw contract balance (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
