// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title AnonymousMessaging
 * @dev A contract for anonymous messages using commitment schemes
 * @author Swift v2 Team
 */
contract AnonymousMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event AnonymousMessageCommitted(
        uint256 indexed messageId,
        bytes32 indexed commitment,
        address recipient,
        uint256 timestamp
    );

    event AnonymousMessageRevealed(
        uint256 indexed messageId,
        address indexed sender,
        uint256 timestamp
    );

    // Structs
    struct AnonymousMessage {
        uint256 id;
        bytes32 senderCommitment;
        address recipient;
        string content;
        uint256 timestamp;
        bool isRevealed;
        address revealedSender;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => AnonymousMessage) public anonymousMessages;
    mapping(address => uint256[]) public recipientMessages;

    // Constants
    uint256 public constant ANONYMOUS_FEE = 0.000007 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Send an anonymous message with commitment
     * @param _recipient Address of the recipient
     * @param _content Message content
     * @param _commitment Hash commitment of sender (keccak256(abi.encodePacked(sender, secret)))
     */
    function sendAnonymousMessage(
        address _recipient,
        string memory _content,
        bytes32 _commitment
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= ANONYMOUS_FEE, "Insufficient fee");
        require(_recipient != address(0), "Invalid recipient");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(_commitment != bytes32(0), "Invalid commitment");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        AnonymousMessage storage message = anonymousMessages[messageId];
        message.id = messageId;
        message.senderCommitment = _commitment;
        message.recipient = _recipient;
        message.content = _content;
        message.timestamp = block.timestamp;
        message.isRevealed = false;

        recipientMessages[_recipient].push(messageId);

        emit AnonymousMessageCommitted(
            messageId,
            _commitment,
            _recipient,
            block.timestamp
        );
    }

    /**
     * @dev Reveal sender identity by providing the secret
     * @param _messageId ID of the message
     * @param _secret Secret used in the commitment
     */
    function revealSender(uint256 _messageId, string memory _secret) 
        external 
        nonReentrant 
    {
        AnonymousMessage storage message = anonymousMessages[_messageId];
        require(!message.isRevealed, "Already revealed");
        
        bytes32 computedCommitment = keccak256(abi.encodePacked(msg.sender, _secret));
        require(computedCommitment == message.senderCommitment, "Invalid proof");

        message.isRevealed = true;
        message.revealedSender = msg.sender;

        emit AnonymousMessageRevealed(_messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Get anonymous message details
     */
    function getAnonymousMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            bytes32 senderCommitment,
            address recipient,
            string memory content,
            uint256 timestamp,
            bool isRevealed,
            address revealedSender
        )
    {
        AnonymousMessage storage message = anonymousMessages[_messageId];
        require(
            msg.sender == message.recipient || 
            (message.isRevealed && msg.sender == message.revealedSender),
            "Not authorized"
        );
        
        return (
            message.id,
            message.senderCommitment,
            message.recipient,
            message.content,
            message.timestamp,
            message.isRevealed,
            message.revealedSender
        );
    }

    /**
     * @dev Get recipient's messages
     */
    function getRecipientMessages(address _recipient) external view returns (uint256[] memory) {
        return recipientMessages[_recipient];
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
