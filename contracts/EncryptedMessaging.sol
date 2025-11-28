// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title EncryptedMessaging
 * @dev A contract for encrypted messages with hash-based verification
 * @author Swift v2 Team
 */
contract EncryptedMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event EncryptedMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed recipient,
        bytes32 contentHash,
        uint256 timestamp
    );

    event MessageDecrypted(
        uint256 indexed messageId,
        address indexed recipient,
        uint256 timestamp
    );

    // Structs
    struct EncryptedMessage {
        uint256 id;
        address sender;
        address recipient;
        bytes32 contentHash;
        string encryptedContent;
        bytes32 decryptionKeyHash;
        uint256 timestamp;
        bool isDecrypted;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => EncryptedMessage) public encryptedMessages;
    mapping(address => uint256[]) public userSentMessages;
    mapping(address => uint256[]) public userReceivedMessages;

    // Constants
    uint256 public constant ENCRYPTION_FEE = 0.000004 ether;
    uint256 public constant MAX_ENCRYPTED_LENGTH = 5000;

    // Modifiers
    modifier messageExists(uint256 _messageId) {
        require(_messageId > 0 && _messageId <= _messageIdCounter.current(), "Message does not exist");
        _;
    }

    modifier onlyRecipient(uint256 _messageId) {
        require(encryptedMessages[_messageId].recipient == msg.sender, "Only recipient can decrypt");
        _;
    }

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Send an encrypted message
     * @param _recipient Address of the recipient
     * @param _encryptedContent Encrypted message content
     * @param _contentHash Hash of the original content for verification
     * @param _decryptionKeyHash Hash of the decryption key
     */
    function sendEncryptedMessage(
        address _recipient,
        string memory _encryptedContent,
        bytes32 _contentHash,
        bytes32 _decryptionKeyHash
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot send to yourself");
        require(msg.value >= ENCRYPTION_FEE, "Insufficient fee");
        require(bytes(_encryptedContent).length > 0, "Empty content");
        require(bytes(_encryptedContent).length <= MAX_ENCRYPTED_LENGTH, "Content too long");
        require(_contentHash != bytes32(0), "Invalid content hash");
        require(_decryptionKeyHash != bytes32(0), "Invalid key hash");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        EncryptedMessage storage message = encryptedMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.recipient = _recipient;
        message.contentHash = _contentHash;
        message.encryptedContent = _encryptedContent;
        message.decryptionKeyHash = _decryptionKeyHash;
        message.timestamp = block.timestamp;
        message.isDecrypted = false;

        userSentMessages[msg.sender].push(messageId);
        userReceivedMessages[_recipient].push(messageId);

        emit EncryptedMessageSent(
            messageId,
            msg.sender,
            _recipient,
            _contentHash,
            block.timestamp
        );
    }

    /**
     * @dev Verify and mark message as decrypted
     * @param _messageId ID of the message
     * @param _decryptionKey The decryption key to verify
     */
    function verifyDecryption(uint256 _messageId, string memory _decryptionKey) 
        external 
        messageExists(_messageId)
        onlyRecipient(_messageId)
    {
        EncryptedMessage storage message = encryptedMessages[_messageId];
        require(!message.isDecrypted, "Already decrypted");
        
        bytes32 providedKeyHash = keccak256(abi.encodePacked(_decryptionKey));
        require(providedKeyHash == message.decryptionKeyHash, "Invalid decryption key");

        message.isDecrypted = true;

        emit MessageDecrypted(_messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Get encrypted message details
     * @param _messageId ID of the message
     */
    function getEncryptedMessage(uint256 _messageId) 
        external 
        view 
        messageExists(_messageId)
        returns (
            uint256 id,
            address sender,
            address recipient,
            bytes32 contentHash,
            string memory encryptedContent,
            uint256 timestamp,
            bool isDecrypted
        )
    {
        EncryptedMessage storage message = encryptedMessages[_messageId];
        require(
            msg.sender == message.sender || msg.sender == message.recipient,
            "Not authorized to view this message"
        );
        
        return (
            message.id,
            message.sender,
            message.recipient,
            message.contentHash,
            message.encryptedContent,
            message.timestamp,
            message.isDecrypted
        );
    }

    /**
     * @dev Get user's sent messages
     */
    function getUserSentMessages(address _user) external view returns (uint256[] memory) {
        return userSentMessages[_user];
    }

    /**
     * @dev Get user's received messages
     */
    function getUserReceivedMessages(address _user) external view returns (uint256[] memory) {
        return userReceivedMessages[_user];
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
