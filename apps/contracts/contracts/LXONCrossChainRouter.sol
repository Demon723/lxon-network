// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title LXONCrossChainRouter
 * @notice Cross-chain router with LayerZero/Wormhole integration
 * 
 * Enhancement 15: Cross-Chain Router Integration
 * - Supports LayerZero-style endpoint interface
 * - Can be adapted for Wormhole or other protocols
 * - Enables token and message bridging
 * - Comprehensive event logging
 * - Flash loan protection
 */
contract LXONCrossChainRouter is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ROUTER_ADMIN = keccak256("ROUTER_ADMIN");
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    // LayerZero-like interface
    ILayerZeroEndpoint public endpoint;

    struct CrossChainRequest {
        bytes32 requestId;
        uint16 dstChainId;
        address destinationAddress;
        bytes payload;
        uint256 nativeFee;
        address zroPaymentAddress;
        bytes adapterParams;
        uint256 timestamp;
        RequestStatus status;
    }

    enum RequestStatus { Pending, Delivered, Failed, Refunded }

    // Events
    event CrossChainRequestSent(
        bytes32 indexed requestId,
        uint16 indexed dstChainId,
        address indexed destinationAddress,
        bytes payload,
        uint256 nativeFee,
        uint256 timestamp
    );

    event CrossChainRequestDelivered(
        bytes32 indexed requestId,
        address indexed destinationAddress,
        uint256 timestamp
    );

    event CrossChainRequestFailed(
        bytes32 indexed requestId,
        string reason,
        uint256 timestamp
    );

    event CrossChainRequestRefunded(
        bytes32 indexed requestId,
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    event EndpointUpdated(address indexed oldEndpoint, address indexed newEndpoint, uint256 timestamp);

    event RelayerAdded(address indexed relayer, uint256 timestamp);
    event RelayerRemoved(address indexed relayer, uint256 timestamp);

    // Circuit breaker events
    event CircuitBreakerTriggered(
        string functionType,
        bool paused,
        address indexed triggerer,
        uint256 timestamp,
        uint256 blockNumber
    );

    mapping(bytes32 => CrossChainRequest) public requests;
    mapping(address => bool) public relayers;
    mapping(uint16 => bool) public supportedChains;

    // Circuit breaker flags
    bool public sendingPaused;
    bool public receivingPaused;

    // Flash loan protection
    uint256 private _routerBalanceBefore;

    modifier onlyRelayer() {
        require(relayers[msg.sender], "Not authorized relayer");
        _;
    }

    modifier whenSendingNotPaused() {
        require(!sendingPaused, "Sending paused");
        _;
    }

    modifier whenReceivingNotPaused() {
        require(!receivingPaused, "Receiving paused");
        _;
    }

    modifier noFlashLoan() {
        _routerBalanceBefore = address(this).balance;
        _;
        require(address(this).balance >= _routerBalanceBefore, "Flash loan detected");
    }

    constructor(address _endpoint) {
        require(_endpoint != address(0), "Zero endpoint");

        endpoint = ILayerZeroEndpoint(_endpoint);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ROUTER_ADMIN, msg.sender);
        _grantRole(RELAYER_ROLE, msg.sender);
    }

    /* --------------------------- Circuit Breakers --------------------------- */

    function triggerCircuitBreaker(
        bool _sendingPaused,
        bool _receivingPaused
    ) external onlyRole(ROUTER_ADMIN) {
        sendingPaused = _sendingPaused;
        receivingPaused = _receivingPaused;

        emit CircuitBreakerTriggered(
            "GLOBAL",
            _sendingPaused || _receivingPaused,
            msg.sender,
            block.timestamp,
            block.number
        );
    }

    /* --------------------------- LayerZero Integration --------------------------- */

    /**
     * @notice Send cross-chain request via LayerZero
     * @param _dstChainId Destination chain ID (LayerZero format)
     * @param _destinationAddress Destination address on target chain
     * @param _payload Payload data
     * @param _nativeFee Native token fee for relayer
     * @param _zroPaymentAddress ZRO payment address (optional)
     * @param _adapterParams Adapter parameters for custom gas settings
     */
    function sendCrossChainRequest(
        uint16 _dstChainId,
        address _destinationAddress,
        bytes calldata _payload,
        uint256 _nativeFee,
        address payable _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable nonReentrant whenNotPaused whenSendingNotPaused noFlashLoan returns (bytes32) {
        return _sendCrossChainRequest(
            _dstChainId,
            _destinationAddress,
            _payload,
            _nativeFee,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    // Shared implementation behind the external entry point and bridgeToken. It carries no
    // modifiers because in-contract callers already run under the same guards; re-entering
    // nonReentrant would revert.
    function _sendCrossChainRequest(
        uint16 _dstChainId,
        address _destinationAddress,
        bytes memory _payload,
        uint256 _nativeFee,
        address payable _zroPaymentAddress,
        bytes memory _adapterParams
    ) private returns (bytes32) {
        require(supportedChains[_dstChainId], "Chain not supported");
        require(_destinationAddress != address(0), "Zero destination");
        require(msg.value >= _nativeFee, "Insufficient native fee");

        bytes32 requestId = keccak256(
            abi.encodePacked(
                msg.sender,
                _dstChainId,
                _destinationAddress,
                _payload,
                block.timestamp
            )
        );

        require(requests[requestId].requestId == bytes32(0), "Request exists");

        // Call LayerZero endpoint
        endpoint.send{value: _nativeFee}(
            _dstChainId,
            abi.encodePacked(_destinationAddress),
            _payload,
            payable(msg.sender),
            _zroPaymentAddress,
            _adapterParams
        );

        requests[requestId] = CrossChainRequest({
            requestId: requestId,
            dstChainId: _dstChainId,
            destinationAddress: _destinationAddress,
            payload: _payload,
            nativeFee: _nativeFee,
            zroPaymentAddress: _zroPaymentAddress,
            adapterParams: _adapterParams,
            timestamp: block.timestamp,
            status: RequestStatus.Pending
        });

        emit CrossChainRequestSent(
            requestId,
            _dstChainId,
            _destinationAddress,
            _payload,
            _nativeFee,
            block.timestamp
        );

        return requestId;
    }

    /**
     * @notice Receive cross-chain request from LayerZero
     * @param _srcChainId Source chain ID
     * @param _srcAddress Source address
     * @param _nonce Nonce for ordering
     * @param _payload Payload data
     */
    function receiveCrossChainRequest(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external nonReentrant whenNotPaused whenReceivingNotPaused {
        require(msg.sender == address(endpoint), "Unauthorized endpoint");

        bytes32 requestId = keccak256(
            abi.encodePacked(
                _srcChainId,
                _srcAddress,
                _nonce,
                _payload
            )
        );

        requests[requestId] = CrossChainRequest({
            requestId: requestId,
            dstChainId: _srcChainId,
            destinationAddress: address(bytes20(_srcAddress)),
            payload: _payload,
            nativeFee: 0,
            zroPaymentAddress: address(0),
            adapterParams: "",
            timestamp: block.timestamp,
            status: RequestStatus.Delivered
        });

        emit CrossChainRequestDelivered(
            requestId,
            address(bytes20(_srcAddress)),
            block.timestamp
        );
    }

    /**
     * @notice Token bridging via LayerZero
     * @param _dstChainId Destination chain ID
     * @param _token Token address to bridge
     * @param _amount Amount to bridge
     * @param _destinationAddress Destination address on target chain
     */
    function bridgeToken(
        uint16 _dstChainId,
        address _token,
        uint256 _amount,
        address _destinationAddress
    ) external payable nonReentrant whenNotPaused whenSendingNotPaused noFlashLoan returns (bytes32) {
        require(supportedChains[_dstChainId], "Chain not supported");
        require(_destinationAddress != address(0), "Zero destination");
        require(_amount > 0, "Zero amount");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        bytes memory payload = abi.encode(_token, _amount, _destinationAddress);

        return _sendCrossChainRequest(
            _dstChainId,
            _destinationAddress,
            payload,
            msg.value,
            payable(address(0)),
            ""
        );
    }

    /* --------------------------- Admin Functions --------------------------- */

    function setEndpoint(address _newEndpoint) external onlyRole(ROUTER_ADMIN) {
        address oldEndpoint = address(endpoint);
        endpoint = ILayerZeroEndpoint(_newEndpoint);
        emit EndpointUpdated(oldEndpoint, _newEndpoint, block.timestamp);
    }

    function addSupportedChain(uint16 _chainId) external onlyRole(ROUTER_ADMIN) {
        supportedChains[_chainId] = true;
    }

    function removeSupportedChain(uint16 _chainId) external onlyRole(ROUTER_ADMIN) {
        supportedChains[_chainId] = false;
    }

    function addRelayer(address _relayer) external onlyRole(ROUTER_ADMIN) {
        require(!relayers[_relayer], "Already relayer");
        relayers[_relayer] = true;
        _grantRole(RELAYER_ROLE, _relayer);
        emit RelayerAdded(_relayer, block.timestamp);
    }

    function removeRelayer(address _relayer) external onlyRole(ROUTER_ADMIN) {
        relayers[_relayer] = false;
        _revokeRole(RELAYER_ROLE, _relayer);
        emit RelayerRemoved(_relayer, block.timestamp);
    }

    function markRequestFailed(bytes32 _requestId, string calldata _reason) external onlyRelayer {
        require(requests[_requestId].requestId == _requestId, "Request not found");
        requests[_requestId].status = RequestStatus.Failed;
        emit CrossChainRequestFailed(_requestId, _reason, block.timestamp);
    }

    function refundRequest(bytes32 _requestId) external onlyRelayer nonReentrant {
        CrossChainRequest storage request = requests[_requestId];
        require(request.requestId == _requestId, "Request not found");
        require(request.status == RequestStatus.Failed, "Request not failed");
        require(request.nativeFee > 0, "No native fee to refund");

        request.status = RequestStatus.Refunded;
        payable(msg.sender).transfer(request.nativeFee);

        emit CrossChainRequestRefunded(_requestId, msg.sender, request.nativeFee, block.timestamp);
    }

    /* --------------------------- View Functions --------------------------- */

    function getRequest(bytes32 _requestId) external view returns (CrossChainRequest memory) {
        return requests[_requestId];
    }

    function isChainSupported(uint16 _chainId) external view returns (bool) {
        return supportedChains[_chainId];
    }

    /* --------------------------- Emergency Functions --------------------------- */

    function emergencyWithdraw(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function emergencyWithdrawNative(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(msg.sender).transfer(_amount);
    }
}

/**
 * @title ILayerZeroEndpoint
 * @notice Simplified LayerZero endpoint interface
 */
interface ILayerZeroEndpoint {
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;
}
