// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title LotteryMessaging
 * @dev Lottery-based messaging with random winner selection
 * @author Swift v2 Team
 * @notice Uses block hash for randomness (simplified, use Chainlink VRF in production)
 */
contract LotteryMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    enum LotteryStatus { ACTIVE, DRAWING, COMPLETED }

    // Events
    event LotteryCreated(
        uint256 indexed lotteryId,
        address indexed creator,
        uint256 prize,
        uint256 endTime,
        uint256 timestamp
    );

    event LotteryEntered(
        uint256 indexed lotteryId,
        address indexed participant,
        string message,
        uint256 timestamp
    );

    event WinnerSelected(
        uint256 indexed lotteryId,
        address indexed winner,
        uint256 prize,
        uint256 timestamp
    );

    // Structs
    struct Lottery {
        uint256 id;
        address creator;
        uint256 prizePool;
        uint256 entryFee;
        uint256 startTime;
        uint256 endTime;
        LotteryStatus status;
        address[] participants;
        mapping(address => string) participantMessages;
        mapping(address => bool) hasEntered;
        address winner;
        uint256 winningIndex;
    }

    // State variables
    Counters.Counter private _lotteryIdCounter;
    mapping(uint256 => Lottery) public lotteries;
    mapping(address => uint256[]) public userLotteries;

    // Constants
    uint256 public constant MIN_PRIZE = 0.001 ether;
    uint256 public constant MIN_ENTRY_FEE = 0.0001 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 500;
    uint256 public constant MIN_DURATION = 3600; // 1 hour
    uint256 public constant MAX_DURATION = 604800; // 7 days

    constructor() {
        _lotteryIdCounter.increment();
    }

    /**
     * @dev Create lottery
     * @param _entryFee Entry fee
     * @param _duration Duration in seconds
     */
    function createLottery(uint256 _entryFee, uint256 _duration) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= MIN_PRIZE, "Prize too small");
        require(_entryFee >= MIN_ENTRY_FEE, "Entry fee too small");
        require(_duration >= MIN_DURATION, "Duration too short");
        require(_duration <= MAX_DURATION, "Duration too long");
        
        uint256 lotteryId = _lotteryIdCounter.current();
        _lotteryIdCounter.increment();

        Lottery storage lottery = lotteries[lotteryId];
        lottery.id = lotteryId;
        lottery.creator = msg.sender;
        lottery.prizePool = msg.value;
        lottery.entryFee = _entryFee;
        lottery.startTime = block.timestamp;
        lottery.endTime = block.timestamp + _duration;
        lottery.status = LotteryStatus.ACTIVE;

        userLotteries[msg.sender].push(lotteryId);

        emit LotteryCreated(
            lotteryId,
            msg.sender,
            msg.value,
            lottery.endTime,
            block.timestamp
        );
    }

    /**
     * @dev Enter lottery with message
     * @param _lotteryId Lottery ID
     * @param _message Entry message
     */
    function enterLottery(uint256 _lotteryId, string memory _message) 
        external 
        payable 
        nonReentrant 
    {
        Lottery storage lottery = lotteries[_lotteryId];
        require(lottery.status == LotteryStatus.ACTIVE, "Lottery not active");
        require(block.timestamp < lottery.endTime, "Lottery ended");
        require(!lottery.hasEntered[msg.sender], "Already entered");
        require(msg.value >= lottery.entryFee, "Insufficient entry fee");
        require(bytes(_message).length > 0, "Message required");
        require(bytes(_message).length <= MAX_MESSAGE_LENGTH, "Message too long");
        
        lottery.participants.push(msg.sender);
        lottery.participantMessages[msg.sender] = _message;
        lottery.hasEntered[msg.sender] = true;
        lottery.prizePool += msg.value;

        userLotteries[msg.sender].push(_lotteryId);

        emit LotteryEntered(_lotteryId, msg.sender, _message, block.timestamp);
    }

    /**
     * @dev Draw winner (simplified randomness)
     * @param _lotteryId Lottery ID
     */
    function drawWinner(uint256 _lotteryId) 
        external 
        nonReentrant 
    {
        Lottery storage lottery = lotteries[_lotteryId];
        require(lottery.status == LotteryStatus.ACTIVE, "Not active");
        require(block.timestamp >= lottery.endTime, "Not ended yet");
        require(lottery.participants.length > 0, "No participants");

        lottery.status = LotteryStatus.DRAWING;

        // Simple randomness using block hash (NOT SECURE for production)
        // Use Chainlink VRF for production
        uint256 randomness = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.difficulty,
                    lottery.participants.length
                )
            )
        );

        uint256 winningIndex = randomness % lottery.participants.length;
        address winner = lottery.participants[winningIndex];

        lottery.winner = winner;
        lottery.winningIndex = winningIndex;
        lottery.status = LotteryStatus.COMPLETED;

        // Transfer prize to winner
        (bool success, ) = payable(winner).call{value: lottery.prizePool}("");
        require(success, "Prize transfer failed");

        emit WinnerSelected(_lotteryId, winner, lottery.prizePool, block.timestamp);
    }

    /**
     * @dev Get lottery details
     */
    function getLottery(uint256 _lotteryId) 
        external 
        view 
        returns (
            uint256 id,
            address creator,
            uint256 prizePool,
            uint256 entryFee,
            uint256 endTime,
            LotteryStatus status,
            uint256 participantCount,
            address winner
        )
    {
        Lottery storage lottery = lotteries[_lotteryId];
        return (
            lottery.id,
            lottery.creator,
            lottery.prizePool,
            lottery.entryFee,
            lottery.endTime,
            lottery.status,
            lottery.participants.length,
            lottery.winner
        );
    }

    /**
     * @dev Get participant message
     */
    function getParticipantMessage(uint256 _lotteryId, address _participant) 
        external 
        view 
        returns (string memory)
    {
        return lotteries[_lotteryId].participantMessages[_participant];
    }

    /**
     * @dev Get lottery participants
     */
    function getLotteryParticipants(uint256 _lotteryId) 
        external 
        view 
        returns (address[] memory)
    {
        return lotteries[_lotteryId].participants;
    }

    /**
     * @dev Get user's lotteries
     */
    function getUserLotteries(address _user) external view returns (uint256[] memory) {
        return userLotteries[_user];
    }

    /**
     * @dev Check if user entered lottery
     */
    function hasUserEntered(uint256 _lotteryId, address _user) 
        external 
        view 
        returns (bool)
    {
        return lotteries[_lotteryId].hasEntered[_user];
    }
}
