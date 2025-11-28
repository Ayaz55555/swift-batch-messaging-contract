// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title CrossChainMessaging
 * @dev A contract with cross-chain message delivery integration
 * @author Swift v2 Team
 * @notice This is a simplified version. Full implementation would require LayerZero/Axelar integration
 */
contract CrossChainMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event CrossChainMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        uint256 destinationChainId,
        address recipient,
        uint256 timestamp
    );

    event CrossChainMessageReceived(
        uint256 indexed messageId,
        uint256 sourceChainId,
        address indexed sender,
        address indexed recipient,
        uint256 timestamp
    );

    // Structs
    struct CrossChainMessage {
        uint256 id;
        address sender;
        address recipient;
        uint256 destinationChainId;
        string content;
        uint256 timestamp;
        bool isDelivered;
        bytes32 messageHash;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => CrossChainMessage) public crossChainMessages;
    mapping(address => uint256[]) public userSentMessages;
    mapping(bytes32 => bool) public processedMessages;

    // Supported chains
    mapping(uint256 => bool) public supportedChains;
    mapping(uint256 => address) public trustedRemotes; // chainId => remote contract address

    // Constants
    uint256 public constant CROSS_CHAIN_FEE = 0.00002 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 1000;

    constructor() {
        _messageIdCounter.increment();
        
        // Add some common chains (example)
        supportedChains[1] = true; // Ethereum
        supportedChains[8453] = true; // Base
        supportedChains[42161] = true; // Arbitrum
        supportedChains[10] = true; // Optimism
    }

    /**
     * @dev Send a cross-chain message
     * @param _destinationChainId Target chain ID
     * @param _recipient Recipient address on destination chain
     * @param _content Message content
     */
    function sendCrossChainMessage(
        uint256 _destinationChainId,
        address _recipient,
        string memory _content
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= CROSS_CHAIN_FEE, "Insufficient fee");
        require(supportedChains[_destinationChainId], "Chain not supported");
        require(_recipient != address(0), "Invalid recipient");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                block.chainid,
                _destinationChainId,
                msg.sender,
                _recipient,
                _content,
                messageId
            )
        );

        CrossChainMessage storage message = crossChainMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.recipient = _recipient;
        message.destinationChainId = _destinationChainId;
        message.content = _content;
        message.timestamp = block.timestamp;
        message.isDelivered = false;
        message.messageHash = messageHash;

        userSentMessages[msg.sender].push(messageId);

        emit CrossChainMessageSent(
            messageId,
            msg.sender,
            _destinationChainId,
            _recipient,
            block.timestamp
        );
    }

    /**
     * @dev Receive a cross-chain message (simplified - would be called by bridge)
     * @param _sourceChainId Source chain ID
     * @param _sender Sender address from source chain
     * @param _recipient Recipient address
     * @param _content Message content
     * @param _messageHash Message hash for verification
     */
    function receiveCrossChainMessage(
        uint256 _sourceChainId,
        address _sender,
        address _recipient,
        string memory _content,
        bytes32 _messageHash
    ) 
        external 
        nonReentrant 
    {
        require(supportedChains[_sourceChainId], "Chain not supported");
        require(!processedMessages[_messageHash], "Message already processed");
        require(_recipient != address(0), "Invalid recipient");
        
        processedMessages[_messageHash] = true;

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        CrossChainMessage storage message = crossChainMessages[messageId];
        message.id = messageId;
        message.sender = _sender;
        message.recipient = _recipient;
        message.destinationChainId = block.chainid;
        message.content = _content;
        message.timestamp = block.timestamp;
        message.isDelivered = true;
        message.messageHash = _messageHash;

        emit CrossChainMessageReceived(
            messageId,
            _sourceChainId,
            _sender,
            _recipient,
            block.timestamp
        );
    }

    /**
     * @dev Add supported chain
     */
    function addSupportedChain(uint256 _chainId, address _trustedRemote) 
        external 
        onlyOwner 
    {
        require(_chainId != block.chainid, "Cannot add current chain");
        supportedChains[_chainId] = true;
        trustedRemotes[_chainId] = _trustedRemote;
    }

    /**
     * @dev Remove supported chain
     */
    function removeSupportedChain(uint256 _chainId) 
        external 
        onlyOwner 
    {
        supportedChains[_chainId] = false;
        delete trustedRemotes[_chainId];
    }

    /**
     * @dev Get cross-chain message details
     */
    function getCrossChainMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address recipient,
            uint256 destinationChainId,
            string memory content,
            uint256 timestamp,
            bool isDelivered,
            bytes32 messageHash
        )
    {
        CrossChainMessage storage message = crossChainMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipient,
            message.destinationChainId,
            message.content,
            message.timestamp,
            message.isDelivered,
            message.messageHash
        );
    }

    /**
     * @dev Get user's sent messages
     */
    function getUserSentMessages(address _user) external view returns (uint256[] memory) {
        return userSentMessages[_user];
    }

    /**
     * @dev Withdraw contract balance (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
