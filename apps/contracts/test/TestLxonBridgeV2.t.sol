// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/LxonBridgeV2.sol";
import "../contracts/AttestationVerifierV2.sol";
import "../contracts/Ed25519SignatureVerifier.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("LXON", "XON") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract TestLxonBridgeV2 is Test {
    LxonBridgeV2 bridge;
    AttestationVerifierV2 attestationVerifier;
    Ed25519SignatureVerifier signatureVerifier;
    MockToken token;
    
    address deployer;
    uint256 deployerPrivateKey;
    address user;
    address recipient;
    
    function setUp() public {
        deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff;
        deployer = vm.addr(deployerPrivateKey);
        user = address(0x1);
        recipient = address(0x2);
        
        // Deploy mock token
        token = new MockToken();
        
        // Deploy signature verifier with deployer as verification service
        signatureVerifier = new Ed25519SignatureVerifier(
            deployer
        );
        
        // Deploy attestation verifier
        attestationVerifier = new AttestationVerifierV2(address(signatureVerifier));
        
        // Deploy bridge
        bridge = new LxonBridgeV2(address(token), address(attestationVerifier));
        
        // Give user some tokens
        token.transfer(user, 1000 * 10**18);
    }
    
    function testInitiateTransfer() public {
        // Give bridge some tokens to transfer
        token.transfer(address(bridge), 1000 * 10**18);
        
        // Approve bridge to spend user's tokens
        vm.prank(user);
        token.approve(address(bridge), 1000 * 10**18);
        
        vm.prank(user);
        bytes32 transferId = bridge.initiateTransfer(recipient, 100 * 10**18);
        
        // Check transfer details
        (address recipientAddr, uint256 amount,, bool completed) = bridge.getTransfer(transferId);
        
        assertEq(recipientAddr, recipient);
        assertEq(amount, 100 * 10**18);
        assertEq(completed, false);
    }
    
    function testCompleteTransferWithAttestation() public {
        // Give bridge some tokens to transfer
        token.transfer(address(bridge), 1000 * 10**18);
        
        // Approve bridge to spend user's tokens
        vm.prank(user);
        token.approve(address(bridge), 1000 * 10**18);
        
        vm.prank(user);
        bytes32 transferId = bridge.initiateTransfer(recipient, 100 * 10**18);
        
        // Generate attestation parameters
        bytes32 attestationId = keccak256(abi.encodePacked(transferId, block.timestamp));
        address validator = deployer;
        bytes32 messageHash = keccak256(abi.encodePacked(transferId));
        bool valid = true;
        uint256 timestamp = block.timestamp;
        
        // Sign the correct message hash (the one attestation verifier expects)
        bytes32 messageHashForSig = keccak256(abi.encodePacked(
            attestationId,
            validator,
            messageHash,
            valid,
            timestamp
        ));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, messageHashForSig);
        
        // Complete transfer
        vm.prank(deployer);
        bridge.completeTransferWithAttestation(
            transferId,
            attestationId,
            validator,
            messageHash,
            valid,
            timestamp,
            r,
            s,
            v
        );
        
        // Check transfer completed
        (, , , bool completed) = bridge.getTransfer(transferId);
        assertTrue(completed);
        
        // Check recipient received tokens
        assertEq(token.balanceOf(recipient), 100 * 10**18);
    }
    
    function testCannotCompleteTwice() public {
        // Give bridge some tokens to transfer
        token.transfer(address(bridge), 1000 * 10**18);
        
        // Approve bridge to spend user's tokens
        vm.prank(user);
        token.approve(address(bridge), 1000 * 10**18);
        
        vm.prank(user);
        bytes32 transferId = bridge.initiateTransfer(recipient, 100 * 10**18);
        
        // Generate attestation parameters
        bytes32 attestationId = keccak256(abi.encodePacked(transferId, block.timestamp));
        address validator = deployer;
        bytes32 messageHash = keccak256(abi.encodePacked(transferId));
        bool valid = true;
        uint256 timestamp = block.timestamp;
        
        // Sign the correct message hash (the one attestation verifier expects)
        bytes32 messageHashForSig = keccak256(abi.encodePacked(
            attestationId,
            validator,
            messageHash,
            valid,
            timestamp
        ));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, messageHashForSig);
        
        // Complete transfer first time
        vm.prank(deployer);
        bridge.completeTransferWithAttestation(
            transferId,
            attestationId,
            validator,
            messageHash,
            valid,
            timestamp,
            r,
            s,
            v
        );
        
        // Try to complete again - should fail
        vm.prank(deployer);
        vm.expectRevert("Transfer already completed");
        bridge.completeTransferWithAttestation(
            transferId,
            attestationId,
            validator,
            messageHash,
            valid,
            timestamp,
            r,
            s,
            v
        );
    }
}
