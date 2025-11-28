// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title AIAgentMessaging
 * @dev A contract with AI agent integration for automated responses
 * @author Swift v2 Team
 * @notice This contract provides hooks for AI agent integration
 */
contract AIAgentMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event MessageSentToAgent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed agentAddress,
        string content,
        uint256 timestamp
    );

    event AgentResponseReceived(
        uint256 indexed messageId,
        uint256 indexed responseId,
        address indexed agentAddress,
        string response,
        uint256 timestamp
    );

    event AgentRegistered(
        address indexed agentAddress,
        string agentName,
        uint256 timestamp
    );

    // Structs
    struct AIAgent {
        address agentAddress;
        string name;
        string description;
        bool isActive;
        uint256 messageCount;
        uint256 responseCount;
    }

    struct AIMessage {
        uint256 id;
        address sender;
        address agentAddress;
        string content;
        uint256 timestamp;
        bool hasResponse;
        uint256 responseId;
    }

    struct AIResponse {
        uint256 id;
        uint256 messageId;
        address agentAddress;
        string response;
        uint256 timestamp;
        uint256 confidence; // 0-100
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    Counters.Counter private _responseIdCounter;
    mapping(address => AIAgent) public aiAgents;
    mapping(uint256 => AIMessage) public aiMessages;
    mapping(uint256 => AIResponse) public aiResponses;
    mapping(address => uint256[]) public userMessages;
    mapping(address => uint256[]) public agentMessages;

    // Constants
    uint256 public constant AI_MESSAGE_FEE = 0.000005 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant MAX_RESPONSE_LENGTH = 3000;

    constructor() {
        _messageIdCounter.increment();
        _responseIdCounter.increment();
    }

    /**
     * @dev Register an AI agent
     * @param _agentAddress Address of the AI agent
     * @param _name Agent name
     * @param _description Agent description
     */
    function registerAgent(
        address _agentAddress,
        string memory _name,
        string memory _description
    ) 
        external 
        onlyOwner 
    {
        require(_agentAddress != address(0), "Invalid agent address");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(!aiAgents[_agentAddress].isActive, "Agent already registered");
        
        AIAgent storage agent = aiAgents[_agentAddress];
        agent.agentAddress = _agentAddress;
        agent.name = _name;
        agent.description = _description;
        agent.isActive = true;
        agent.messageCount = 0;
        agent.responseCount = 0;

        emit AgentRegistered(_agentAddress, _name, block.timestamp);
    }

    /**
     * @dev Send message to AI agent
     * @param _agentAddress Address of the AI agent
     * @param _content Message content
     */
    function sendMessageToAgent(
        address _agentAddress,
        string memory _content
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= AI_MESSAGE_FEE, "Insufficient fee");
        require(aiAgents[_agentAddress].isActive, "Agent not active");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        AIMessage storage message = aiMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.agentAddress = _agentAddress;
        message.content = _content;
        message.timestamp = block.timestamp;
        message.hasResponse = false;

        aiAgents[_agentAddress].messageCount++;
        userMessages[msg.sender].push(messageId);
        agentMessages[_agentAddress].push(messageId);

        emit MessageSentToAgent(
            messageId,
            msg.sender,
            _agentAddress,
            _content,
            block.timestamp
        );
    }

    /**
     * @dev Agent submits response (only agent can call)
     * @param _messageId ID of the message
     * @param _response Response content
     * @param _confidence Confidence level 0-100
     */
    function submitAgentResponse(
        uint256 _messageId,
        string memory _response,
        uint256 _confidence
    ) 
        external 
        nonReentrant 
    {
        AIMessage storage message = aiMessages[_messageId];
        require(message.agentAddress == msg.sender, "Only assigned agent can respond");
        require(!message.hasResponse, "Already responded");
        require(bytes(_response).length > 0, "Empty response");
        require(bytes(_response).length <= MAX_RESPONSE_LENGTH, "Response too long");
        require(_confidence <= 100, "Invalid confidence level");
        
        uint256 responseId = _responseIdCounter.current();
        _responseIdCounter.increment();

        AIResponse storage response = aiResponses[responseId];
        response.id = responseId;
        response.messageId = _messageId;
        response.agentAddress = msg.sender;
        response.response = _response;
        response.timestamp = block.timestamp;
        response.confidence = _confidence;

        message.hasResponse = true;
        message.responseId = responseId;
        aiAgents[msg.sender].responseCount++;

        emit AgentResponseReceived(
            _messageId,
            responseId,
            msg.sender,
            _response,
            block.timestamp
        );
    }

    /**
     * @dev Toggle agent active status
     */
    function toggleAgentStatus(address _agentAddress) 
        external 
        onlyOwner 
    {
        require(aiAgents[_agentAddress].agentAddress != address(0), "Agent not registered");
        aiAgents[_agentAddress].isActive = !aiAgents[_agentAddress].isActive;
    }

    /**
     * @dev Get AI agent details
     */
    function getAIAgent(address _agentAddress) 
        external 
        view 
        returns (
            address agentAddress,
            string memory name,
            string memory description,
            bool isActive,
            uint256 messageCount,
            uint256 responseCount
        )
    {
        AIAgent storage agent = aiAgents[_agentAddress];
        return (
            agent.agentAddress,
            agent.name,
            agent.description,
            agent.isActive,
            agent.messageCount,
            agent.responseCount
        );
    }

    /**
     * @dev Get AI message details
     */
    function getAIMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address agentAddress,
            string memory content,
            uint256 timestamp,
            bool hasResponse,
            uint256 responseId
        )
    {
        AIMessage storage message = aiMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.agentAddress,
            message.content,
            message.timestamp,
            message.hasResponse,
            message.responseId
        );
    }

    /**
     * @dev Get AI response details
     */
    function getAIResponse(uint256 _responseId) 
        external 
        view 
        returns (
            uint256 id,
            uint256 messageId,
            address agentAddress,
            string memory response,
            uint256 timestamp,
            uint256 confidence
        )
    {
        AIResponse storage response = aiResponses[_responseId];
        return (
            response.id,
            response.messageId,
            response.agentAddress,
            response.response,
            response.timestamp,
            response.confidence
        );
    }

    /**
     * @dev Get user's messages
     */
    function getUserMessages(address _user) external view returns (uint256[] memory) {
        return userMessages[_user];
    }

    /**
     * @dev Get agent's messages
     */
    function getAgentMessages(address _agent) external view returns (uint256[] memory) {
        return agentMessages[_agent];
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
