// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title GamingMessaging
 * @dev In-game messaging with achievement rewards and player interactions
 * @author Swift v2 Team
 */
contract GamingMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event GameMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed recipient,
        string gameContext,
        uint256 timestamp
    );

    event AchievementUnlocked(
        address indexed player,
        string achievementName,
        uint256 rewardPoints,
        uint256 timestamp
    );

    event RewardClaimed(
        address indexed player,
        uint256 amount,
        uint256 timestamp
    );

    // Structs
    struct GameMessage {
        uint256 id;
        address sender;
        address recipient;
        string content;
        string gameContext; // e.g., "battle", "trade", "guild"
        uint256 timestamp;
        bool hasReward;
        uint256 rewardPoints;
    }

    struct Achievement {
        string name;
        string description;
        uint256 rewardPoints;
        bool isActive;
    }

    struct PlayerStats {
        uint256 messagesSet;
        uint256 totalPoints;
        uint256 claimedRewards;
        mapping(string => bool) achievementsUnlocked;
        string[] unlockedAchievements;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => GameMessage) public gameMessages;
    mapping(address => PlayerStats) public playerStats;
    mapping(address => uint256[]) public userMessages;
    mapping(string => Achievement) public achievements;
    string[] public achievementNames;

    // Constants
    uint256 public constant MAX_MESSAGE_LENGTH = 500;
    uint256 public constant MESSAGE_FEE = 0.000001 ether;
    uint256 public constant POINTS_PER_MESSAGE = 10;
    uint256 public constant REWARD_RATE = 100; // 100 points = 0.0001 ether

    constructor() {
        _messageIdCounter.increment();
        
        // Initialize default achievements
        _createAchievement("First Message", "Send your first message", 50);
        _createAchievement("Social Butterfly", "Send 100 messages", 500);
        _createAchievement("Master Communicator", "Send 1000 messages", 5000);
    }

    /**
     * @dev Internal function to create achievement
     */
    function _createAchievement(
        string memory _name,
        string memory _description,
        uint256 _rewardPoints
    ) internal {
        achievements[_name] = Achievement({
            name: _name,
            description: _description,
            rewardPoints: _rewardPoints,
            isActive: true
        });
        achievementNames.push(_name);
    }

    /**
     * @dev Create custom achievement (only owner)
     */
    function createAchievement(
        string memory _name,
        string memory _description,
        uint256 _rewardPoints
    ) external onlyOwner {
        require(bytes(achievements[_name].name).length == 0, "Achievement exists");
        _createAchievement(_name, _description, _rewardPoints);
    }

    /**
     * @dev Send game message
     * @param _recipient Recipient address
     * @param _content Message content
     * @param _gameContext Game context
     */
    function sendGameMessage(
        address _recipient,
        string memory _content,
        string memory _gameContext
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= MESSAGE_FEE, "Insufficient fee");
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot send to yourself");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        GameMessage storage message = gameMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.recipient = _recipient;
        message.content = _content;
        message.gameContext = _gameContext;
        message.timestamp = block.timestamp;
        message.hasReward = true;
        message.rewardPoints = POINTS_PER_MESSAGE;

        // Update player stats
        PlayerStats storage stats = playerStats[msg.sender];
        stats.messagesSet++;
        stats.totalPoints += POINTS_PER_MESSAGE;

        userMessages[msg.sender].push(messageId);

        // Check for achievements
        _checkAchievements(msg.sender);

        emit GameMessageSent(
            messageId,
            msg.sender,
            _recipient,
            _gameContext,
            block.timestamp
        );
    }

    /**
     * @dev Check and unlock achievements
     */
    function _checkAchievements(address _player) internal {
        PlayerStats storage stats = playerStats[_player];

        // First Message
        if (stats.messagesSet == 1 && !stats.achievementsUnlocked["First Message"]) {
            _unlockAchievement(_player, "First Message");
        }

        // Social Butterfly
        if (stats.messagesSet >= 100 && !stats.achievementsUnlocked["Social Butterfly"]) {
            _unlockAchievement(_player, "Social Butterfly");
        }

        // Master Communicator
        if (stats.messagesSet >= 1000 && !stats.achievementsUnlocked["Master Communicator"]) {
            _unlockAchievement(_player, "Master Communicator");
        }
    }

    /**
     * @dev Unlock achievement for player
     */
    function _unlockAchievement(address _player, string memory _achievementName) internal {
        PlayerStats storage stats = playerStats[_player];
        Achievement storage achievement = achievements[_achievementName];

        if (!stats.achievementsUnlocked[_achievementName] && achievement.isActive) {
            stats.achievementsUnlocked[_achievementName] = true;
            stats.unlockedAchievements.push(_achievementName);
            stats.totalPoints += achievement.rewardPoints;

            emit AchievementUnlocked(
                _player,
                _achievementName,
                achievement.rewardPoints,
                block.timestamp
            );
        }
    }

    /**
     * @dev Claim rewards
     * @param _points Points to convert to rewards
     */
    function claimRewards(uint256 _points) 
        external 
        nonReentrant 
    {
        PlayerStats storage stats = playerStats[msg.sender];
        require(stats.totalPoints >= _points, "Insufficient points");
        require(_points >= REWARD_RATE, "Minimum 100 points to claim");

        stats.totalPoints -= _points;
        uint256 rewardAmount = (_points * 1 ether) / (REWARD_RATE * 10000);
        stats.claimedRewards += rewardAmount;

        require(address(this).balance >= rewardAmount, "Insufficient contract balance");

        (bool success, ) = payable(msg.sender).call{value: rewardAmount}("");
        require(success, "Reward transfer failed");

        emit RewardClaimed(msg.sender, rewardAmount, block.timestamp);
    }

    /**
     * @dev Get player stats
     */
    function getPlayerStats(address _player) 
        external 
        view 
        returns (
            uint256 messagesSent,
            uint256 totalPoints,
            uint256 claimedRewards,
            string[] memory unlockedAchievements
        )
    {
        PlayerStats storage stats = playerStats[_player];
        return (
            stats.messagesSet,
            stats.totalPoints,
            stats.claimedRewards,
            stats.unlockedAchievements
        );
    }

    /**
     * @dev Check if achievement is unlocked
     */
    function hasAchievement(address _player, string memory _achievementName) 
        external 
        view 
        returns (bool)
    {
        return playerStats[_player].achievementsUnlocked[_achievementName];
    }

    /**
     * @dev Get game message details
     */
    function getGameMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address recipient,
            string memory content,
            string memory gameContext,
            uint256 timestamp,
            uint256 rewardPoints
        )
    {
        GameMessage storage message = gameMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipient,
            message.content,
            message.gameContext,
            message.timestamp,
            message.rewardPoints
        );
    }

    /**
     * @dev Get all achievements
     */
    function getAllAchievements() external view returns (string[] memory) {
        return achievementNames;
    }

    /**
     * @dev Fund contract for rewards (anyone can fund)
     */
    function fundRewards() external payable {
        require(msg.value > 0, "Must send value");
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
