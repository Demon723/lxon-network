// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/LxonTokenEnhanced.sol";
import "../contracts/LXONBridgeEnhanced.sol";

/**
 * @title MigrateBridgeTokenRef
 * @notice One deployment that finishes the two fixes agreed on 2026-10-19:
 *
 *         1. Dead validator-staking path. The bridge did `IERC20(address(this))` inside
 *            addValidator/removeValidator/slashValidator, but it is not a token, so every
 *            call reverted in SafeERC20. The bridge now takes an immutable `lxonToken`.
 *         2. Decimal convention. Chain 724 is 18 decimals (LXONNativeToken is 18 too), but
 *            LxonTokenEnhanced was funded with 100_000_000 * 1e6, so totalSupply was 1e14
 *            wei — 0.0001 LXON — which made MIN_VALIDATOR_STAKE (10000 * 1e18) unreachable.
 *            Rather than redeploy the token (which would also orphan the bridge's immutable
 *            timelock), this supplies the shortfall: grant MINTER to the deployer and mint
 *            up to 100_000_000e18.
 *
 *         It also proves the staking path works on-chain by adding the deployer as a
 *         validator and immediately removing it, which returns the stake.
 *
 *         Side effects to be aware of: the deployer keeps MINTER_ROLE on the token after
 *         this run (it already holds DEFAULT_ADMIN, so it could re-grant itself anyway),
 *         and the pending timelock operation against bridge v2 is cancelled because the v2
 *         bridge is being retired.
 *
 *         Not idempotent: re-running deploys another bridge and re-mints up to the same
 *         target (the mint is guarded, the bridge is not).
 *
 *         Run:
 *           PRIVATE_KEY="0x$(cat ../../lxon-evm-node/geth/privatekey.txt)" \
 *             forge script script/MigrateBridgeTokenRef.s.sol --rpc-url lxon --broadcast
 */
contract MigrateBridgeTokenRef is Script {
    address constant TOKEN = 0x99801A78639975D448EEb2f8a807738DC8Df67Dc;
    // Bridge v2 (timelock-gated, no token reference) — being retired by this script.
    address constant V2_BRIDGE = 0xB4927aBef5247A3ab53C3074f469f3cFd4D470d1;
    // Operation queued against V2_BRIDGE on 2026-10-19, ready 2026-10-21T21:46:31Z.
    bytes32 constant V2_OPERATION =
        0xe977672a7a7ad67e3b5b1ff1686c6eef1406eed1fda75de4f2452309a872235e;

    uint256 constant TARGET_SUPPLY = 100_000_000 * 1e18;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        LxonTokenEnhanced token = LxonTokenEnhanced(TOKEN);

        bytes32 minter = token.MINTER_ROLE();
        bytes32 burner = token.BURNER_ROLE();
        uint256 supplyBefore = token.totalSupply();

        vm.startBroadcast(pk);

        // (2) supply correction — mint only the shortfall, never more.
        if (!token.hasRole(minter, deployer)) {
            token.grantRole(minter, deployer);
        }
        if (token.totalSupply() < TARGET_SUPPLY) {
            token.mint(deployer, TARGET_SUPPLY - token.totalSupply());
        }
        uint256 supplyAfter = token.totalSupply();

        // (1) bridge with the token wired in.
        LXONBridgeEnhanced bridge = new LXONBridgeEnhanced(address(0), TOKEN, TOKEN);

        // Move wrapped-asset powers off v2 (grant before revoke: no gap for transfers).
        token.grantRole(minter, address(bridge));
        token.grantRole(burner, address(bridge));
        token.revokeRole(minter, V2_BRIDGE);
        token.revokeRole(burner, V2_BRIDGE);

        // Retire the operation that was queued against v2 and re-queue it on v3.
        token.cancelTimelock(V2_OPERATION);
        bytes32 op = token.scheduleTimelock(
            address(bridge), abi.encodeWithSignature("setMinConfirmations(uint256)", uint256(3))
        );

        // Prove the previously-dead staking path executes against the real token, then
        // hand the stake back so the bridge is left with no validators registered.
        uint256 stake = bridge.MIN_VALIDATOR_STAKE();
        token.approve(address(bridge), stake);
        bridge.addValidator(deployer, stake);
        uint256 stakedFrom = token.balanceOf(address(bridge));
        bridge.removeValidator(deployer);
        uint256 stakedAfter = token.balanceOf(address(bridge));

        vm.stopBroadcast();

        console.log("deployer            :", deployer);
        console.log("totalSupply before  :", supplyBefore);
        console.log("totalSupply after   :", supplyAfter);
        console.log("decimals            :", token.decimals());
        console.log("v2 bridge           :", V2_BRIDGE);
        console.log("v3 bridge           :", address(bridge));
        console.log("v3 timelock         :", address(bridge.timelock()));
        console.log("v3 lxonToken        :", address(bridge.lxonToken()));
        console.log("minter v3/v2        :", vm.toString(token.hasRole(minter, address(bridge))),
            vm.toString(token.hasRole(minter, V2_BRIDGE)));
        console.log("burner v3/v2        :", vm.toString(token.hasRole(burner, address(bridge))),
            vm.toString(token.hasRole(burner, V2_BRIDGE)));
        console.log("stake held during addValidator:", stakedFrom);
        console.log("stake after remove (must be 0):", stakedAfter);
        console.log("MIN_VALIDATOR_STAKE :", stake);
        console.log("v2 op cancelled     :", vm.toString(token.getTimelock(V2_OPERATION).cancelled));
        console.log("v3 op ready at unix :", vm.toString(token.getTimelock(op).executeTime));
        console.log("NOTE                : the printed op id is simulated; read the");
        console.log("                      TimelockScheduled event for the on-chain id.");
    }
}
