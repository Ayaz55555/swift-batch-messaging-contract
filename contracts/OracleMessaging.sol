// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";


/**
 * @title OracleMessaging
 * @dev Oracle data feed integration for verified external data messaging
 * @author Swift v2 Team
 */
contract OracleMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event OracleRegistered(
        address indexed oracle,
        string dataType,
        uint256 timestamp
    );

    event DataMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        string dataType,
        bytes32 dataHash,
        uint256 timestamp
    );

    event DataVerified(
        uint256 indexed messageId,
        address indexed oracle,
        bool isValid,
        uint256 timestamp
    );

    // Structs
    struct Oracle {
        address oracleAddress;
        string dataType;
        bool isActive;
        uint256 verificationCount;
    }

    struct DataMessage {
        uint256 id;
        address sender;
        address[] recipients;
        string dataType;
        string data;
        bytes32 dataHash;
        uint256 timestamp;
        bool isVerified;
        address verifiedBy;
        uint256 confidence; // 0-100
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(address => Oracle) public oracles;
    mapping(uint256 => DataMessage) public dataMessages;
    mapping(address => uint256[]) public userMessages;
    mapping(string => address[]) public oraclesByType;

    address[] public allOracles;

    // Constants
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_DATA_LENGTH = 5000;
    uint256 public constant ORACLE_MESSAGE_FEE = 0.00001 ether;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Register oracle (only owner)
     * @param _oracle Oracle address
     * @param _dataType Type of data oracle provides
     */
    function registerOracle(address _oracle, string memory _dataType) 
        external 
        onlyOwner 
    {
        require(_oracle != address(0), "Invalid oracle");
        require(bytes(_dataType).length > 0, "Data type required");
        require(oracles[_oracle].oracleAddress == address(0), "Already registered");
        
        oracles[_oracle] = Oracle({
            oracleAddress: _oracle,
            dataType: _dataType,
            isActive: true,
            verificationCount: 0
        });

        allOracles.push(_oracle);
        oraclesByType[_dataType].push(_oracle);

        emit OracleRegistered(_oracle, _dataType, block.timestamp);
    }

    /**
     * @dev Send data message
     * @param _recipients Recipients
     * @param _dataType Data type
     * @param _data Data content
     */
    function sendDataMessage(
        address[] memory _recipients,
        string memory _dataType,
        string memory _data
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= ORACLE_MESSAGE_FEE, "Insufficient fee");
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_data).length > 0, "Empty data");
        require(bytes(_data).length <= MAX_DATA_LENGTH, "Data too long");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        bytes32 dataHash = keccak256(abi.encodePacked(_data, _dataType, msg.sender));

        DataMessage storage message = dataMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.dataType = _dataType;
        message.data = _data;
        message.dataHash = dataHash;
        message.timestamp = block.timestamp;
        message.isVerified = false;
        message.confidence = 0;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        userMessages[msg.sender].push(messageId);

        emit DataMessageSent(
            messageId,
            msg.sender,
            _dataType,
            dataHash,
            block.timestamp
        );
    }

    /**
     * @dev Verify data message (oracle only)
     * @param _messageId Message ID
     * @param _isValid Whether data is valid
     * @param _confidence Confidence level 0-100
     */
    function verifyDataMessage(
        uint256 _messageId,
        bool _isValid,
        uint256 _confidence
    ) 
        external 
        nonReentrant 
    {
        Oracle storage oracle = oracles[msg.sender];
        require(oracle.isActive, "Not an active oracle");
        require(_confidence <= 100, "Invalid confidence");
        
        DataMessage storage message = dataMessages[_messageId];
        require(!message.isVerified, "Already verified");
        require(
            keccak256(bytes(oracle.dataType)) == keccak256(bytes(message.dataType)),
            "Oracle type mismatch"
        );

        if (_isValid) {
            message.isVerified = true;
            message.verifiedBy = msg.sender;
            message.confidence = _confidence;
            oracle.verificationCount++;
        }

        emit DataVerified(_messageId, msg.sender, _isValid, block.timestamp);
    }

    /**
     * @dev Toggle oracle status
     */
    function toggleOracleStatus(address _oracle) 
        external 
        onlyOwner 
    {
        Oracle storage oracle = oracles[_oracle];
        require(oracle.oracleAddress != address(0), "Oracle not registered");
        
        oracle.isActive = !oracle.isActive;
    }

    /**
     * @dev Get data message
     */
    function getDataMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address[] memory recipients,
            string memory dataType,
            string memory data,
            bytes32 dataHash,
            uint256 timestamp,
            bool isVerified,
            address verifiedBy,
            uint256 confidence
        )
    {
        DataMessage storage message = dataMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipients,
            message.dataType,
            message.data,
            message.dataHash,
            message.timestamp,
            message.isVerified,
            message.verifiedBy,
            message.confidence
        );
    }

    /**
     * @dev Get oracle details
     */
    function getOracle(address _oracle) 
        external 
        view 
        returns (
            address oracleAddress,
            string memory dataType,
            bool isActive,
            uint256 verificationCount
        )
    {
        Oracle storage oracle = oracles[_oracle];
        return (
            oracle.oracleAddress,
            oracle.dataType,
            oracle.isActive,
            oracle.verificationCount
        );
    }

    /**
     * @dev Get oracles by data type
     */
    function getOraclesByType(string memory _dataType) 
        external 
        view 
        returns (address[] memory)
    {
        return oraclesByType[_dataType];
    }

    /**
     * @dev Get all oracles
     */
    function getAllOracles() external view returns (address[] memory) {
        return allOracles;
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
