// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title StakingMessaging
 * @dev Stake tokens to unlock messaging privileges
 * @author Swift v2 Team
 */
contract StakingMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    enum StakingTier { BRONZE, SILVER, GOLD, PLATINUM }

    // Events
    event TokensStaked(
        address indexed user,
        uint256 amount,
        StakingTier tier,
        uint256 timestamp
    );

    event TokensUnstaked(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    event StakedMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        StakingTier tier,
        uint256 timestamp
    );

    // Structs
    struct StakingInfo {
        uint256 stakedAmount;
        uint256 stakeTime;
        StakingTier tier;
        uint256 messagesSent;
        uint256 lastMessageTime;
    }

    struct StakedMessage {
        uint256 id;
        address sender;
        address[] recipients;
        string content;
        StakingTier senderTier;
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(address => StakingInfo) public stakingInfo;
    mapping(uint256 => StakedMessage) public stakedMessages;
    mapping(address => uint256[]) public userMessages;

    // Staking token (can be set to any ERC20)
    IERC20 public stakingToken;

    // Tier thresholds
    uint256 public constant BRONZE_STAKE = 100 * 10**18; // 100 tokens
    uint256 public constant SILVER_STAKE = 500 * 10**18; // 500 tokens
    uint256 public constant GOLD_STAKE = 2000 * 10**18; // 2000 tokens
    uint256 public constant PLATINUM_STAKE = 10000 * 10**18; // 10000 tokens

    // Messaging limits per tier
    uint256 public constant BRONZE_LIMIT = 10; // messages per day
    uint256 public constant SILVER_LIMIT = 50;
    uint256 public constant GOLD_LIMIT = 200;
    uint256 public constant PLATINUM_LIMIT = 1000;

    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant DAY_IN_SECONDS = 86400;

    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
        _messageIdCounter.increment();
    }

    /**
     * @dev Stake tokens
     * @param _amount Amount to stake
     */
    function stake(uint256 _amount) 
        external 
        nonReentrant 
    {
        require(_amount > 0, "Amount must be greater than 0");
        require(
            stakingToken.transferFrom(msg.sender, address(this), _amount),
            "Stake transfer failed"
        );

        StakingInfo storage info = stakingInfo[msg.sender];
        info.stakedAmount += _amount;
        if (info.stakeTime == 0) {
            info.stakeTime = block.timestamp;
        }

        // Determine tier
        info.tier = _determineTier(info.stakedAmount);

        emit TokensStaked(msg.sender, _amount, info.tier, block.timestamp);
    }

    /**
     * @dev Unstake tokens
     * @param _amount Amount to unstake
     */
    function unstake(uint256 _amount) 
        external 
        nonReentrant 
    {
        StakingInfo storage info = stakingInfo[msg.sender];
        require(info.stakedAmount >= _amount, "Insufficient staked amount");

        info.stakedAmount -= _amount;
        info.tier = _determineTier(info.stakedAmount);

        require(
            stakingToken.transfer(msg.sender, _amount),
            "Unstake transfer failed"
        );

        emit TokensUnstaked(msg.sender, _amount, block.timestamp);
    }

    /**
     * @dev Determine staking tier
     */
    function _determineTier(uint256 _amount) internal pure returns (StakingTier) {
        if (_amount >= PLATINUM_STAKE) return StakingTier.PLATINUM;
        if (_amount >= GOLD_STAKE) return StakingTier.GOLD;
        if (_amount >= SILVER_STAKE) return StakingTier.SILVER;
        if (_amount >= BRONZE_STAKE) return StakingTier.BRONZE;
        revert("Insufficient stake for any tier");
    }

    /**
     * @dev Get message limit for tier
     */
    function _getTierLimit(StakingTier _tier) internal pure returns (uint256) {
        if (_tier == StakingTier.PLATINUM) return PLATINUM_LIMIT;
        if (_tier == StakingTier.GOLD) return GOLD_LIMIT;
        if (_tier == StakingTier.SILVER) return SILVER_LIMIT;
        return BRONZE_LIMIT;
    }

    /**
     * @dev Send staked message
     * @param _recipients Recipients
     * @param _content Message content
     */
    function sendStakedMessage(
        address[] memory _recipients,
        string memory _content
    ) 
        external 
        nonReentrant 
    {
        StakingInfo storage info = stakingInfo[msg.sender];
        require(info.stakedAmount >= BRONZE_STAKE, "Insufficient stake");
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");

        // Check daily limit
        if (block.timestamp - info.lastMessageTime < DAY_IN_SECONDS) {
            uint256 dailyLimit = _getTierLimit(info.tier);
            require(info.messagesSent < dailyLimit, "Daily limit reached");
        } else {
            // Reset daily counter
            info.messagesSent = 0;
            info.lastMessageTime = block.timestamp;
        }

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        StakedMessage storage message = stakedMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.content = _content;
        message.senderTier = info.tier;
        message.timestamp = block.timestamp;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        info.messagesSent++;
        userMessages[msg.sender].push(messageId);

        emit StakedMessageSent(messageId, msg.sender, info.tier, block.timestamp);
    }

    /**
     * @dev Get staking info
     */
    function getStakingInfo(address _user) 
        external 
        view 
        returns (
            uint256 stakedAmount,
            uint256 stakeTime,
            StakingTier tier,
            uint256 messagesSent,
            uint256 messagesRemaining
        )
    {
        StakingInfo storage info = stakingInfo[_user];
        uint256 limit = _getTierLimit(info.tier);
        uint256 remaining = 0;
        
        if (block.timestamp - info.lastMessageTime < DAY_IN_SECONDS) {
            remaining = limit > info.messagesSent ? limit - info.messagesSent : 0;
        } else {
            remaining = limit;
        }

        return (
            info.stakedAmount,
            info.stakeTime,
            info.tier,
            info.messagesSent,
            remaining
        );
    }

    /**
     * @dev Get staked message
     */
    function getStakedMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address[] memory recipients,
            string memory content,
            StakingTier senderTier,
            uint256 timestamp
        )
    {
        StakedMessage storage message = stakedMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipients,
            message.content,
            message.senderTier,
            message.timestamp
        );
    }

    /**
     * @dev Get user's messages
     */
    function getUserMessages(address _user) external view returns (uint256[] memory) {
        return userMessages[_user];
    }

    /**
     * @dev Update staking token (only owner)
     */
    function setStakingToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        stakingToken = IERC20(_token);
    }
}
