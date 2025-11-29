// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title NFTGatedMessaging
 * @dev NFT ownership-based access control for exclusive messaging
 * @author Swift v2 Team
 */
contract NFTGatedMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event NFTGateCreated(
        uint256 indexed gateId,
        address indexed nftContract,
        address creator,
        uint256 timestamp
    );

    event GatedMessageSent(
        uint256 indexed messageId,
        uint256 indexed gateId,
        address indexed sender,
        uint256 timestamp
    );

    // Structs
    struct NFTGate {
        uint256 id;
        address nftContract;
        address creator;
        string name;
        string description;
        bool requiresSpecificToken;
        uint256[] allowedTokenIds;
        mapping(uint256 => bool) isTokenAllowed;
        bool isActive;
        uint256 createdAt;
    }

    struct GatedMessage {
        uint256 id;
        uint256 gateId;
        address sender;
        address[] recipients;
        string content;
        uint256 timestamp;
        uint256 senderTokenId;
    }

    // State variables
    Counters.Counter private _gateIdCounter;
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => NFTGate) public nftGates;
    mapping(uint256 => GatedMessage) public gatedMessages;
    mapping(address => uint256[]) public userGates;
    mapping(address => uint256[]) public userMessages;
    mapping(uint256 => uint256[]) public gateMessages;

    // Constants
    uint256 public constant MAX_RECIPIENTS = 100;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant GATE_CREATION_FEE = 0.00001 ether;
    uint256 public constant GATED_MESSAGE_FEE = 0.000005 ether;

    constructor() {
        _gateIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create NFT gate
     * @param _nftContract NFT contract address
     * @param _name Gate name
     * @param _description Gate description
     * @param _requiresSpecificToken Require specific token IDs
     * @param _allowedTokenIds Allowed token IDs (if specific)
     */
    function createNFTGate(
        address _nftContract,
        string memory _name,
        string memory _description,
        bool _requiresSpecificToken,
        uint256[] memory _allowedTokenIds
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= GATE_CREATION_FEE, "Insufficient fee");
        require(_nftContract != address(0), "Invalid NFT contract");
        require(bytes(_name).length > 0, "Name cannot be empty");
        
        uint256 gateId = _gateIdCounter.current();
        _gateIdCounter.increment();

        NFTGate storage gate = nftGates[gateId];
        gate.id = gateId;
        gate.nftContract = _nftContract;
        gate.creator = msg.sender;
        gate.name = _name;
        gate.description = _description;
        gate.requiresSpecificToken = _requiresSpecificToken;
        gate.isActive = true;
        gate.createdAt = block.timestamp;

        if (_requiresSpecificToken) {
            for (uint256 i = 0; i < _allowedTokenIds.length; i++) {
                gate.allowedTokenIds.push(_allowedTokenIds[i]);
                gate.isTokenAllowed[_allowedTokenIds[i]] = true;
            }
        }

        userGates[msg.sender].push(gateId);

        emit NFTGateCreated(gateId, _nftContract, msg.sender, block.timestamp);
    }

    /**
     * @dev Verify NFT ownership
     */
    function verifyNFTOwnership(
        uint256 _gateId,
        address _user
    ) 
        public 
        view 
        returns (bool, uint256)
    {
        NFTGate storage gate = nftGates[_gateId];
        IERC721 nft = IERC721(gate.nftContract);

        // Check balance
        uint256 balance = nft.balanceOf(_user);
        if (balance == 0) {
            return (false, 0);
        }

        // If specific tokens required, check for valid token
        if (gate.requiresSpecificToken) {
            for (uint256 i = 0; i < gate.allowedTokenIds.length; i++) {
                uint256 tokenId = gate.allowedTokenIds[i];
                try nft.ownerOf(tokenId) returns (address owner) {
                    if (owner == _user) {
                        return (true, tokenId);
                    }
                } catch {
                    continue;
                }
            }
            return (false, 0);
        }

        // Any NFT from collection is valid
        return (true, 0);
    }

    /**
     * @dev Send gated message
     * @param _gateId Gate ID
     * @param _recipients Recipient addresses (must own NFT)
     * @param _content Message content
     */
    function sendGatedMessage(
        uint256 _gateId,
        address[] memory _recipients,
        string memory _content
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= GATED_MESSAGE_FEE, "Insufficient fee");
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        NFTGate storage gate = nftGates[_gateId];
        require(gate.isActive, "Gate not active");

        // Verify sender owns NFT
        (bool senderHasNFT, uint256 senderTokenId) = verifyNFTOwnership(_gateId, msg.sender);
        require(senderHasNFT, "Sender doesn't own required NFT");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        GatedMessage storage message = gatedMessages[messageId];
        message.id = messageId;
        message.gateId = _gateId;
        message.sender = msg.sender;
        message.content = _content;
        message.timestamp = block.timestamp;
        message.senderTokenId = senderTokenId;

        // Verify all recipients own NFT
        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] == address(0) || _recipients[i] == msg.sender) {
                continue;
            }

            (bool hasNFT, ) = verifyNFTOwnership(_gateId, _recipients[i]);
            if (hasNFT) {
                message.recipients.push(_recipients[i]);
            }
        }

        require(message.recipients.length > 0, "No valid NFT-holding recipients");

        userMessages[msg.sender].push(messageId);
        gateMessages[_gateId].push(messageId);

        emit GatedMessageSent(messageId, _gateId, msg.sender, block.timestamp);
    }

    /**
     * @dev Toggle gate active status
     */
    function toggleGateStatus(uint256 _gateId) 
        external 
    {
        NFTGate storage gate = nftGates[_gateId];
        require(gate.creator == msg.sender, "Only creator can toggle");
        
        gate.isActive = !gate.isActive;
    }

    /**
     * @dev Get NFT gate details
     */
    function getNFTGate(uint256 _gateId) 
        external 
        view 
        returns (
            uint256 id,
            address nftContract,
            address creator,
            string memory name,
            string memory description,
            bool requiresSpecificToken,
            uint256[] memory allowedTokenIds,
            bool isActive,
            uint256 createdAt
        )
    {
        NFTGate storage gate = nftGates[_gateId];
        return (
            gate.id,
            gate.nftContract,
            gate.creator,
            gate.name,
            gate.description,
            gate.requiresSpecificToken,
            gate.allowedTokenIds,
            gate.isActive,
            gate.createdAt
        );
    }

    /**
     * @dev Get gated message details
     */
    function getGatedMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            uint256 gateId,
            address sender,
            address[] memory recipients,
            string memory content,
            uint256 timestamp,
            uint256 senderTokenId
        )
    {
        GatedMessage storage message = gatedMessages[_messageId];
        return (
            message.id,
            message.gateId,
            message.sender,
            message.recipients,
            message.content,
            message.timestamp,
            message.senderTokenId
        );
    }

    /**
     * @dev Get user's gates
     */
    function getUserGates(address _user) external view returns (uint256[] memory) {
        return userGates[_user];
    }

    /**
     * @dev Get gate's messages
     */
    function getGateMessages(uint256 _gateId) external view returns (uint256[] memory) {
        return gateMessages[_gateId];
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
