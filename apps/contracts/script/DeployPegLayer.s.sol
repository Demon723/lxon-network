// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {WETH9} from "../contracts/WETH.sol";
import {LXON} from "../contracts/LXON.sol";
import {Pair} from "../contracts/Pair.sol";
import {Router} from "../contracts/Router.sol";
import {PegStabilityModule} from "../contracts/PegStabilityModule.sol";
import {PegAutomatorV2} from "../contracts/PegAutomatorV2.sol";

contract DeployPegLayer is Script {
    uint256 constant CHAIN_ID = 724;
    address constant WLXON = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address constant LXON_ADDRESS = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        //console.log("Deploying Peg Layer to Chain ID", CHAIN_ID);
        //console.log("Deployer:", vm.addr(deployerPrivateKey));

        vm.deal(DEPLOYER, 10000 ether);
        vm.startBroadcast(deployerPrivateKey);

        WETH9(WLXON).deposit{value: 1000 ether}();
        LXON(LXON_ADDRESS).mint(DEPLOYER, 1000, bytes32(0));

        Pair newPair = new Pair(WLXON, 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0);
        Router newRouter = new Router(WLXON, 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0, address(newPair));
        PegStabilityModule psm = new PegStabilityModule(WLXON, WLXON, 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0, address(newRouter), DEPLOYER);
        PegAutomatorV2 automator = new PegAutomatorV2(WLXON, WLXON, address(newRouter), address(newPair), address(psm), 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0, DEPLOYER);

        psm.setAutomator(address(automator));

        IERC20Metadata(WLXON).transfer(address(newPair), 1000e18);
        IERC20Metadata(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0).transfer(address(newPair), 1000);

        newPair.mint(DEPLOYER);

        //console.log("Pair:", address(newPair));
        //console.log("Router:", address(newRouter));
        //console.log("PSM:", address(psm));
        //console.log("Automator:", address(automator));

        vm.stopBroadcast();
    }
}
