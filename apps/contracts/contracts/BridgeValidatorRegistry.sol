// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title BridgeValidatorRegistry
 * @notice Registry for managing bridge validators with timelock governance
 */
contract BridgeValidatorRegistry is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    
    address public admin;
    address public timelock;
    
    mapping(address => bool) public isValidator;
    address[] public validators;
    uint256 public threshold;
    
    mapping(bytes32 => uint256) public transferNonces;
    
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event ThresholdUpdated(uint256 newThreshold);
    event AdminUpdated(address indexed newAdmin);
    event TimelockUpdated(address indexed newTimelock);
    event TransferNonceIncremented(bytes32 indexed transferId, uint256 newNonce);
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    function initialize(
        address _admin,
        address[] memory _validators,
        uint256 _threshold,
        address _timelock
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_threshold > 0 && _threshold <= _validators.length, "Invalid threshold");
        require(_timelock != address(0), "Invalid timelock");
        
        admin = _admin;
        timelock = _timelock;
        threshold = _threshold;
        
        for (uint256 i = 0; i < _validators.length; i++) {
            isValidator[_validators[i]] = true;
            validators.push(_validators[i]);
            emit ValidatorAdded(_validators[i]);
        }
        
        _grantRole(ADMIN_ROLE, _timelock);
    }
    
    modifier onlyAdmin() {
        require(msg.sender == admin || hasRole(ADMIN_ROLE, msg.sender), "REG: FORBIDDEN");
        _;
    }
    
    function addValidator(address _validator) external onlyAdmin {
        require(!isValidator[_validator], "Already validator");
        isValidator[_validator] = true;
        validators.push(_validator);
        emit ValidatorAdded(_validator);
    }
    
    function removeValidator(address _validator) external onlyAdmin {
        require(isValidator[_validator], "Not validator");
        isValidator[_validator] = false;
        
        // Remove from array
        for (uint256 i = 0; i < validators.length; i++) {
            if (validators[i] == _validator) {
                validators[i] = validators[validators.length - 1];
                validators.pop();
                break;
            }
        }
        
        emit ValidatorRemoved(_validator);
    }
    
    function setThreshold(uint256 _threshold) external onlyAdmin {
        require(_threshold > 0 && _threshold <= validators.length, "Invalid threshold");
        threshold = _threshold;
        emit ThresholdUpdated(_threshold);
    }
    
    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
        emit AdminUpdated(_admin);
    }
    
    function setTimelock(address _timelock) external onlyAdmin {
        timelock = _timelock;
        _grantRole(ADMIN_ROLE, _timelock);
        emit TimelockUpdated(_timelock);
    }
    
    function incrementTransferNonce(bytes32 _transferId) external onlyAdmin {
        transferNonces[_transferId]++;
        emit TransferNonceIncremented(_transferId, transferNonces[_transferId]);
    }
    
    function attestationDigest(
        uint256 _fromChainId,
        uint256 _toChainId,
        address _bridge,
        bytes32 _transferId,
        address _token,
        uint256 _amount,
        address _recipient
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                _fromChainId,
                _toChainId,
                _bridge,
                _transferId,
                _token,
                _amount,
                _recipient
            )
        );
    }
    
    function getValidators() external view returns (address[] memory) {
        return validators;
    }
    
    function getValidatorCount() external view returns (uint256) {
        return validators.length;
    }
}
