// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title DonationMessaging
 * @dev A contract where message sending includes optional donation amounts
 * @author Swift v2 Team
 */
contract DonationMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event DonationMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed recipient,
        uint256 donationAmount,
        uint256 timestamp
    );

    event DonationReceived(
        address indexed recipient,
        address indexed sender,
        uint256 amount,
        uint256 timestamp
    );

    // Structs
    struct DonationMessage {
        uint256 id;
        address sender;
        address recipient;
        string content;
        uint256 donationAmount;
        uint256 timestamp;
        bool isDonationClaimed;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => DonationMessage) public donationMessages;
    mapping(address => uint256[]) public userSentMessages;
    mapping(address => uint256[]) public userReceivedMessages;
    mapping(address => uint256) public totalDonationsReceived;
    mapping(address => uint256) public totalDonationsSent;

    // Constants
    uint256 public constant MESSAGE_FEE = 0.000002 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant MIN_DONATION = 0.00001 ether;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Send a message with donation
     * @param _recipient Address of the recipient
     * @param _content Message content
     */
    function sendDonationMessage(
        address _recipient,
        string memory _content
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot send to yourself");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(msg.value >= MESSAGE_FEE, "Insufficient payment");
        
        uint256 donationAmount = msg.value - MESSAGE_FEE;
        require(donationAmount >= MIN_DONATION, "Donation too small");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        DonationMessage storage message = donationMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.recipient = _recipient;
        message.content = _content;
        message.donationAmount = donationAmount;
        message.timestamp = block.timestamp;
        message.isDonationClaimed = false;

        userSentMessages[msg.sender].push(messageId);
        userReceivedMessages[_recipient].push(messageId);
        totalDonationsSent[msg.sender] += donationAmount;

        emit DonationMessageSent(
            messageId,
            msg.sender,
            _recipient,
            donationAmount,
            block.timestamp
        );
    }

    /**
     * @dev Claim donation for a message
     * @param _messageId ID of the message
     */
    function claimDonation(uint256 _messageId) 
        external 
        nonReentrant 
    {
        DonationMessage storage message = donationMessages[_messageId];
        require(message.recipient == msg.sender, "Only recipient can claim");
        require(!message.isDonationClaimed, "Already claimed");

        message.isDonationClaimed = true;
        totalDonationsReceived[msg.sender] += message.donationAmount;

        (bool success, ) = payable(msg.sender).call{value: message.donationAmount}("");
        require(success, "Donation transfer failed");

        emit DonationReceived(
            msg.sender,
            message.sender,
            message.donationAmount,
            block.timestamp
        );
    }

    /**
     * @dev Get donation message details
     */
    function getDonationMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address recipient,
            string memory content,
            uint256 donationAmount,
            uint256 timestamp,
            bool isDonationClaimed
        )
    {
        DonationMessage storage message = donationMessages[_messageId];
        require(
            msg.sender == message.sender || msg.sender == message.recipient,
            "Not authorized"
        );
        
        return (
            message.id,
            message.sender,
            message.recipient,
            message.content,
            message.donationAmount,
            message.timestamp,
            message.isDonationClaimed
        );
    }

    /**
     * @dev Get user's total donations received
     */
    function getTotalDonationsReceived(address _user) external view returns (uint256) {
        return totalDonationsReceived[_user];
    }

    /**
     * @dev Get user's total donations sent
     */
    function getTotalDonationsSent(address _user) external view returns (uint256) {
        return totalDonationsSent[_user];
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
