// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LXON} from "../contracts/LXON.sol";
import {EurPegStabilityModule} from "../contracts/EurPegStabilityModule.sol";

contract MintFounder is Script {
    function run() external {
        address deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address founder = 0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3;
        address lxonAddr = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
        
        // Increase ceiling and mint 100K LXON to founder
        vm.startBroadcast(deployer);
        LXON(lxonAddr).updateCeiling(2000000000, bytes32(0));
        LXON(lxonAddr).mint(founder, 10000000, bytes32(0));
        vm.stopBroadcast();
        //console.log("Founder LXON balance:", IERC20(lxonAddr).balanceOf(founder));
    }
}
