// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/LxonTokenEnhanced.sol";
import "../contracts/LXONBridgeEnhanced.sol";

/**
 * @title MigrateBridgeTimelock
 * @notice SUPERSEDED. Ran on 2026-10-19 and produced bridge v2 (0xb4927aBef5247A3ab53C
 *         3074f469f3cFd4D470d1). Kept for the record; it will revert if re-run (the stale
 *         operation it cancels is already cancelled). Its constructor call was updated to
 *         the three-argument form so the project still builds. The live migration is
 *         script/MigrateBridgeTokenRef.s.sol.
 * @notice Replaces the live LXONBridgeEnhanced (0xbc18..8330) with a version whose
 *         parameter setters are gated on the timelock instead of DEFAULT_ADMIN_ROLE, then
 *         moves the token's MINTER/BURNER grants and the queued operation across.
 *
 *         Why a redeploy: `timelock` is immutable (set in the constructor), and the old
 *         bridge's setters all required DEFAULT_ADMIN_ROLE, which the token does not hold —
 *         so token.executeTimelock() against it reverted with TIMELOCK_EXECUTION_FAILED.
 *
 *         Chain: LXON 724. Idempotency: none — running this twice deploys a second bridge
 *         and re-points the grants. Check the printed addresses before broadcasting.
 *
 *         Run:
 *           PRIVATE_KEY="0x$(cat ../../lxon-evm-node/geth/privatekey.txt)" \
 *             forge script script/MigrateBridgeTimelock.s.sol \
 *             --rpc-url lxon --broadcast
 */
contract MigrateBridgeTimelock is Script {
    // Deployed on 2026-10-19; see deployments/lxon-chain-724.json.
    address constant TOKEN = 0x99801A78639975D448EEb2f8a807738DC8Df67Dc;
    address constant OLD_BRIDGE = 0xbC18D2886EbeFEe91F6E820114b1D976F1be8330;
    // TimelockScheduled op targeting the old bridge (setMinConfirmations(3)), ready
    // 2026-10-21T05:11Z. It can never succeed, so cancel it rather than leave it queued.
    bytes32 constant STALE_OPERATION =
        0x2b530303a6a6b69ef05d94864660686abb391cc7de2a0b0a254c962f1718e655;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        LxonTokenEnhanced token = LxonTokenEnhanced(TOKEN);

        vm.startBroadcast(pk);

        LXONBridgeEnhanced bridge = new LXONBridgeEnhanced(address(0), TOKEN, TOKEN);

        // Move the wrapped-asset powers from the old bridge to the new one. Order matters:
        // grant first so no inbound/outbound transfer window finds the bridge un-mintable.
        token.grantRole(token.MINTER_ROLE(), address(bridge));
        token.grantRole(token.BURNER_ROLE(), address(bridge));
        token.revokeRole(token.MINTER_ROLE(), OLD_BRIDGE);
        token.revokeRole(token.BURNER_ROLE(), OLD_BRIDGE);

        // Drop the operation that was queued against the old bridge, then queue the same
        // intent against the new one. It executes after token.TIMELOCK_DELAY().
        token.cancelTimelock(STALE_OPERATION);

        bytes32 op = token.scheduleTimelock(
            address(bridge), abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(3))
        );

        vm.stopBroadcast();

        console.log("deployer           :", deployer);
        console.log("old bridge         :", OLD_BRIDGE);
        console.log("new bridge         :", address(bridge));
        console.log("new bridge timelock:", address(bridge.timelock()));
        console.log("new minConfirmations:", vm.toString(bridge.minConfirmations()));
        console.log("new maxTransferAmount:", vm.toString(bridge.maxTransferAmount()));
        console.log("minter on new      :", vm.toString(token.hasRole(token.MINTER_ROLE(), address(bridge))));
        console.log("minter on old      :", vm.toString(token.hasRole(token.MINTER_ROLE(), OLD_BRIDGE)));
        console.log("burner on new      :", vm.toString(token.hasRole(token.BURNER_ROLE(), address(bridge))));
        console.log("burner on old      :", vm.toString(token.hasRole(token.BURNER_ROLE(), OLD_BRIDGE)));
        console.log("admin on token->bridge (must stay false):",
            vm.toString(bridge.hasRole(bridge.DEFAULT_ADMIN_ROLE(), TOKEN)));
        console.log("stale op cancelled :", vm.toString(token.getTimelock(STALE_OPERATION).cancelled));
        console.log("new op id          :", vm.toString(op));
        console.log("new op ready at    :", vm.toString(token.getTimelock(op).executeTime));
        console.log("delay hours        :", (token.TIMELOCK_DELAY() / 3600));
        // WARNING: the id printed above is the SIMULATED one. operationId is
        // keccak256(target, data, block.timestamp + DELAY), and the broadcast simulation
        // runs a second or two before the real block, so the on-chain id differs (observed:
        // script said 0xdef4299d…, chain stored 0xe977672a…). Read the TimelockScheduled
        // event from the schedule transaction, not this console line.
    }
}
