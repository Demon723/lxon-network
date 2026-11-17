// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/LxonTokenEnhanced.sol";
import "../contracts/LXONBridgeEnhanced.sol";

/**
 * @title DeployHighPriorityEnhancements
 * @notice Deployment script for high-priority security and gas optimizations
 * 
 * High Priority Enhancements:
 * 1. Multi-sig validator signatures (Bridge security)
 * 2. Timelock for admin functions (Governance security)
 * 3. Permit/ERC2612 to token (Gas optimization)
 */
contract DeployHighPriorityEnhancements is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Enhanced Token with Timelock and Permit
        LxonTokenEnhanced token = new LxonTokenEnhanced(
            deployer,              // admin (gets DEFAULT_ADMIN_ROLE and TIMELOCK_ADMIN)
            deployer,              // initial holder
            100_000_000 * 1e18    // 100M LXON at the chain's 18-decimal convention
        );

        console.log("LxonTokenEnhanced deployed at:", address(token));
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());
        console.log("Decimals:", token.decimals());
        console.log("Total Supply:", token.totalSupply());
        console.log("TimeLock Delay:", token.TIMELOCK_DELAY());

        // Deploy Enhanced Bridge with Multi-sig Validator Signatures.
        // The token doubles as the timelock: the bridge's parameter setters accept
        // calls only from this address, so admin changes must go through
        // token.scheduleTimelock -> 48h -> token.executeTimelock.
        // Note: Price feed address set to zero for now (can be updated later, via timelock)
        LXONBridgeEnhanced bridge = new LXONBridgeEnhanced(address(0), address(token), address(token));

        console.log("LXONBridgeEnhanced deployed at:", address(bridge));
        console.log("Min Confirmations:", bridge.minConfirmations());
        console.log("Max Transfer Amount:", bridge.maxTransferAmount());

        // Grant MINTER_ROLE to bridge so it can mint wrapped tokens
        token.grantRole(token.MINTER_ROLE(), address(bridge));
        token.grantRole(token.BURNER_ROLE(), address(bridge));

        console.log("Granted MINTER_ROLE to bridge");
        console.log("Granted BURNER_ROLE to bridge");

        // Set up timelock for critical bridge operations
        // Example: Set min confirmations via timelock
        bytes memory setData = abi.encodeWithSignature(
            "setMinConfirmations(uint256)",
            uint256(3)  // Require 3 validator signatures
        );

        bytes32 timelockId = token.scheduleTimelock(address(bridge), setData);
        console.log("Timelock scheduled for setMinConfirmations:", vm.toString(timelockId));
        console.log("Execute after 48 hours");

        vm.stopBroadcast();
    }
}
