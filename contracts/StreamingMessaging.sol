// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title StreamingMessaging
 * @dev Continuous payment streaming per message with real-time settlements
 * @author Swift v2 Team
 */
contract StreamingMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event StreamStarted(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        uint256 ratePerSecond,
        uint256 timestamp
    );

    event StreamStopped(
        uint256 indexed streamId,
        uint256 amountStreamed,
        uint256 timestamp
    );

    event MessageStreamed(
        uint256 indexed messageId,
        uint256 indexed streamId,
        string content,
        uint256 timestamp
    );

    // Structs
    struct PaymentStream {
        uint256 id;
        address sender;
        address recipient;
        uint256 ratePerSecond; // wei per second
        uint256 deposit; // Total deposited amount
        uint256 startTime;
        uint256 stopTime;
        uint256 withdrawn;
        bool isActive;
    }

    struct StreamMessage {
        uint256 id;
        uint256 streamId;
        address sender;
        address recipient;
        string content;
        uint256 timestamp;
        uint256 streamedAmount;
    }

    // State variables
    Counters.Counter private _streamIdCounter;
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => PaymentStream) public paymentStreams;
    mapping(uint256 => StreamMessage) public streamMessages;
    mapping(address => uint256[]) public userStreams;
    mapping(address => uint256[]) public userMessages;

    // Constants
    uint256 public constant MAX_MESSAGE_LENGTH = 1000;
    uint256 public constant MIN_STREAM_RATE = 1000; // Min 1000 wei/second
    uint256 public constant MIN_DEPOSIT = 1000000; // Min deposit

    constructor() {
        _streamIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Start payment stream
     * @param _recipient Recipient address
     * @param _ratePerSecond Payment rate per second
     */
    function startStream(address _recipient, uint256 _ratePerSecond) 
        external 
        payable 
        nonReentrant 
    {
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot stream to yourself");
        require(_ratePerSecond >= MIN_STREAM_RATE, "Rate too low");
        require(msg.value >= MIN_DEPOSIT, "Deposit too low");
        
        uint256 streamId = _streamIdCounter.current();
        _streamIdCounter.increment();

        PaymentStream storage stream = paymentStreams[streamId];
        stream.id = streamId;
        stream.sender = msg.sender;
        stream.recipient = _recipient;
        stream.ratePerSecond = _ratePerSecond;
        stream.deposit = msg.value;
        stream.startTime = block.timestamp;
        stream.stopTime = 0;
        stream.withdrawn = 0;
        stream.isActive = true;

        userStreams[msg.sender].push(streamId);

        emit StreamStarted(
            streamId,
            msg.sender,
            _recipient,
            _ratePerSecond,
            block.timestamp
        );
    }

    /**
     * @dev Send message with active stream
     * @param _streamId Active stream ID
     * @param _content Message content
     */
    function sendStreamMessage(uint256 _streamId, string memory _content) 
        external 
        nonReentrant 
    {
        PaymentStream storage stream = paymentStreams[_streamId];
        require(stream.sender == msg.sender, "Not stream owner");
        require(stream.isActive, "Stream not active");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        uint256 streamedAmount = _calculateStreamedAmount(_streamId);

        StreamMessage storage message = streamMessages[messageId];
        message.id = messageId;
        message.streamId = _streamId;
        message.sender = msg.sender;
        message.recipient = stream.recipient;
        message.content = _content;
        message.timestamp = block.timestamp;
        message.streamedAmount = streamedAmount;

        userMessages[msg.sender].push(messageId);

        emit MessageStreamed(messageId, _streamId, _content, block.timestamp);
    }

    /**
     * @dev Calculate streamed amount
     */
    function _calculateStreamedAmount(uint256 _streamId) 
        internal 
        view 
        returns (uint256)
    {
        PaymentStream storage stream = paymentStreams[_streamId];
        
        if (!stream.isActive && stream.stopTime > 0) {
            uint256 duration = stream.stopTime - stream.startTime;
            return duration * stream.ratePerSecond;
        }
        
        uint256 duration = block.timestamp - stream.startTime;
        uint256 streamed = duration * stream.ratePerSecond;
        
        // Cap at deposit
        if (streamed > stream.deposit) {
            return stream.deposit;
        }
        
        return streamed;
    }

    /**
     * @dev Withdraw streamed funds (recipient)
     * @param _streamId Stream ID
     */
    function withdrawStream(uint256 _streamId) 
        external 
        nonReentrant 
    {
        PaymentStream storage stream = paymentStreams[_streamId];
        require(stream.recipient == msg.sender, "Not recipient");
        
        uint256 streamed = _calculateStreamedAmount(_streamId);
        uint256 available = streamed - stream.withdrawn;
        require(available > 0, "Nothing to withdraw");

        stream.withdrawn += available;

        (bool success, ) = payable(msg.sender).call{value: available}("");
        require(success, "Withdrawal failed");
    }

    /**
     * @dev Stop stream
     * @param _streamId Stream ID
     */
    function stopStream(uint256 _streamId) 
        external 
        nonReentrant 
    {
        PaymentStream storage stream = paymentStreams[_streamId];
        require(stream.sender == msg.sender, "Not stream owner");
        require(stream.isActive, "Stream not active");

        stream.isActive = false;
        stream.stopTime = block.timestamp;

        uint256 streamed = _calculateStreamedAmount(_streamId);
        uint256 refund = stream.deposit - streamed;

        // Refund unstreamed amount to sender
        if (refund > 0) {
            (bool success, ) = payable(msg.sender).call{value: refund}("");
            require(success, "Refund failed");
        }

        emit StreamStopped(_streamId, streamed, block.timestamp);
    }

    /**
     * @dev Get stream details
     */
    function getStream(uint256 _streamId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address recipient,
            uint256 ratePerSecond,
            uint256 deposit,
            uint256 startTime,
            uint256 stopTime,
            uint256 withdrawn,
            bool isActive,
            uint256 streamedAmount
        )
    {
        PaymentStream storage stream = paymentStreams[_streamId];
        return (
            stream.id,
            stream.sender,
            stream.recipient,
            stream.ratePerSecond,
            stream.deposit,
            stream.startTime,
            stream.stopTime,
            stream.withdrawn,
            stream.isActive,
            _calculateStreamedAmount(_streamId)
        );
    }

    /**
     * @dev Get stream message details
     */
    function getStreamMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            uint256 streamId,
            address sender,
            address recipient,
            string memory content,
            uint256 timestamp,
            uint256 streamedAmount
        )
    {
        StreamMessage storage message = streamMessages[_messageId];
        return (
            message.id,
            message.streamId,
            message.sender,
            message.recipient,
            message.content,
            message.timestamp,
            message.streamedAmount
        );
    }

    /**
     * @dev Get user's streams
     */
    function getUserStreams(address _user) external view returns (uint256[] memory) {
        return userStreams[_user];
    }

    /**
     * @dev Get user's messages
     */
    function getUserMessages(address _user) external view returns (uint256[] memory) {
        return userMessages[_user];
    }

    /**
     * @dev Get available balance for withdrawal
     */
    function getAvailableBalance(uint256 _streamId, address _user) 
        external 
        view 
        returns (uint256)
    {
        PaymentStream storage stream = paymentStreams[_streamId];
        require(stream.recipient == _user, "Not recipient");
        
        uint256 streamed = _calculateStreamedAmount(_streamId);
        return streamed - stream.withdrawn;
    }
}
