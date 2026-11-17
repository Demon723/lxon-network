// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {BitGoAdapter} from "../../src/custody/BitGoAdapter.sol";

contract BitGoAdapterTest is Test {
    BitGoAdapter adapter;
    uint256 signerPk = 0xA11CE;
    address signer;

    function setUp() public {
        signer = vm.addr(signerPk);
        adapter = new BitGoAdapter(signer, 9999);
    }

    function test_verify_valid_signature() public view {
        bytes32 ref = keccak256("deposit-1");
        address to = address(0xB0B);
        uint256 amount = 1 ether;

        bytes32 message = keccak256(abi.encodePacked(ref, to, amount, uint256(9999)));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, ethHash);
        bytes memory proof = abi.encodePacked(r, s, v);

        assertTrue(adapter.verifyDeposit(ref, to, amount, proof));
    }

    function test_reject_wrong_signer() public {
        bytes32 ref = keccak256("deposit-2");
        bytes32 message = keccak256(abi.encodePacked(ref, address(0xB0B), uint256(1), uint256(9999)));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, ethHash);
        bytes memory proof = abi.encodePacked(r, s, v);
        assertFalse(adapter.verifyDeposit(ref, address(0xB0B), 1, proof));
    }
}