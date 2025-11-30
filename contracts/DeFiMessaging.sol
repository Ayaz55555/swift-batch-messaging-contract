// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeFiMessaging
 * @dev DeFi protocol integration with liquidity pool messaging
 * @author Swift v2 Team
 */
contract DeFiMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event LiquidityPoolCreated(
        uint256 indexed poolId,
        address tokenA,
        address tokenB,
        uint256 timestamp
    );

    event LiquidityMessageSent(
        uint256 indexed messageId,
        uint256 indexed poolId,
        address indexed sender,
        uint256 timestamp
    );

    event YieldClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    // Structs
    struct LiquidityPool {
        uint256 id;
        address tokenA;
        address tokenB;
        uint256 totalLiquidity;
        mapping(address => uint256) userLiquidity;
        address[] liquidityProviders;
        bool isActive;
    }

    struct DeFiMessage {
        uint256 id;
        uint256 poolId;
        address sender;
        address[] recipients;
        string content;
        uint256 liquidityRequired;
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _poolIdCounter;
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => LiquidityPool) public liquidityPools;
    mapping(uint256 => DeFiMessage) public defiMessages;
    mapping(address => uint256[]) public userMessages;
    mapping(address => uint256) public userYield;

    // Constants
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant MIN_LIQUIDITY = 1000000000000000; // 0.001 ETH
    uint256 public constant YIELD_RATE = 100; // 1% per message

    constructor() {
        _poolIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create liquidity pool
     * @param _tokenA First token address
     * @param _tokenB Second token address
     */
    function createLiquidityPool(address _tokenA, address _tokenB) 
        external 
        onlyOwner 
    {
        require(_tokenA != address(0) && _tokenB != address(0), "Invalid tokens");
        require(_tokenA != _tokenB, "Same token");
        
        uint256 poolId = _poolIdCounter.current();
        _poolIdCounter.increment();

        LiquidityPool storage pool = liquidityPools[poolId];
        pool.id = poolId;
        pool.tokenA = _tokenA;
        pool.tokenB = _tokenB;
        pool.totalLiquidity = 0;
        pool.isActive = true;

        emit LiquidityPoolCreated(poolId, _tokenA, _tokenB, block.timestamp);
    }

    /**
     * @dev Add liquidity to pool
     * @param _poolId Pool ID
     * @param _amount Amount to add
     */
    function addLiquidity(uint256 _poolId, uint256 _amount) 
        external 
        payable 
        nonReentrant 
    {
        LiquidityPool storage pool = liquidityPools[_poolId];
        require(pool.isActive, "Pool not active");
        require(msg.value >= _amount, "Insufficient payment");
        require(_amount >= MIN_LIQUIDITY, "Amount too small");

        if (pool.userLiquidity[msg.sender] == 0) {
            pool.liquidityProviders.push(msg.sender);
        }

        pool.userLiquidity[msg.sender] += _amount;
        pool.totalLiquidity += _amount;
    }

    /**
     * @dev Send DeFi message (requires liquidity)
     * @param _poolId Liquidity pool ID
     * @param _recipients Recipients
     * @param _content Message content
     */
    function sendDeFiMessage(
        uint256 _poolId,
        address[] memory _recipients,
        string memory _content
    ) 
        external 
        nonReentrant 
    {
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        LiquidityPool storage pool = liquidityPools[_poolId];
        require(pool.isActive, "Pool not active");
        require(pool.userLiquidity[msg.sender] >= MIN_LIQUIDITY, "Insufficient liquidity");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        DeFiMessage storage message = defiMessages[messageId];
        message.id = messageId;
        message.poolId = _poolId;
        message.sender = msg.sender;
        message.content = _content;
        message.liquidityRequired = MIN_LIQUIDITY;
        message.timestamp = block.timestamp;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        // Accrue yield for liquidity provider
        uint256 yield = (pool.userLiquidity[msg.sender] * YIELD_RATE) / 10000;
        userYield[msg.sender] += yield;

        userMessages[msg.sender].push(messageId);

        emit LiquidityMessageSent(messageId, _poolId, msg.sender, block.timestamp);
    }

    /**
     * @dev Claim accrued yield
     */
    function claimYield() 
        external 
        nonReentrant 
    {
        uint256 yield = userYield[msg.sender];
        require(yield > 0, "No yield to claim");
        require(address(this).balance >= yield, "Insufficient contract balance");

        userYield[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: yield}("");
        require(success, "Yield claim failed");

        emit YieldClaimed(msg.sender, yield, block.timestamp);
    }

    /**
     * @dev Remove liquidity from pool
     * @param _poolId Pool ID
     * @param _amount Amount to remove
     */
    function removeLiquidity(uint256 _poolId, uint256 _amount) 
        external 
        nonReentrant 
    {
        LiquidityPool storage pool = liquidityPools[_poolId];
        require(pool.userLiquidity[msg.sender] >= _amount, "Insufficient liquidity");

        pool.userLiquidity[msg.sender] -= _amount;
        pool.totalLiquidity -= _amount;

        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "Withdrawal failed");
    }

    /**
     * @dev Get pool details
     */
    function getPool(uint256 _poolId) 
        external 
        view 
        returns (
            uint256 id,
            address tokenA,
            address tokenB,
            uint256 totalLiquidity,
            bool isActive
        )
    {
        LiquidityPool storage pool = liquidityPools[_poolId];
        return (
            pool.id,
            pool.tokenA,
            pool.tokenB,
            pool.totalLiquidity,
            pool.isActive
        );
    }

    /**
     * @dev Get user liquidity in pool
     */
    function getUserLiquidity(uint256 _poolId, address _user) 
        external 
        view 
        returns (uint256)
    {
        return liquidityPools[_poolId].userLiquidity[_user];
    }

    /**
     * @dev Get DeFi message
     */
    function getDeFiMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            uint256 poolId,
            address sender,
            address[] memory recipients,
            string memory content,
            uint256 timestamp
        )
    {
        DeFiMessage storage message = defiMessages[_messageId];
        return (
            message.id,
            message.poolId,
            message.sender,
            message.recipients,
            message.content,
            message.timestamp
        );
    }

    /**
     * @dev Get user's yield
     */
    function getUserYield(address _user) external view returns (uint256) {
        return userYield[_user];
    }

    /**
     * @dev Fund contract (for yield payouts)
     */
    function fundContract() external payable {
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
