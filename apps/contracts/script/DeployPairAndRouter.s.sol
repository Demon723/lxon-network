// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WETH9} from "../contracts/WETH.sol";
import {ERC20Mock} from "../contracts/ERC20Mock.sol";
import {LXON} from "../contracts/LXON.sol";
import {Pair} from "../contracts/Pair.sol";
import {Router} from "../contracts/Router.sol";
import {EurPegStabilityModule} from "../contracts/EurPegStabilityModule.sol";

contract DeployPairAndRouter is Script {
    WETH9 public weth;
    ERC20Mock public eurc;
    LXON public lxon;
    Pair public pair;
    Router public router;
    EurPegStabilityModule public psm;
    address public deployer;

    function run() external {
        deployer = vm.envAddress("DEPLOYER");
        vm.deal(deployer, 10000 ether);
        
        vm.startBroadcast(deployer);

        weth = new WETH9();
        eurc = new ERC20Mock("EURC", "EURC", 6);
        lxon = new LXON(deployer);
        pair = new Pair(address(weth), address(lxon));
        router = new Router(address(weth), address(lxon), address(pair));
        psm = new EurPegStabilityModule(address(eurc), address(lxon), deployer);

        vm.stopBroadcast();

        vm.startBroadcast(deployer);
        LXON(address(lxon)).grantRole(LXON(address(lxon)).MINT_ROLE(), deployer);
        LXON(address(lxon)).grantRole(LXON(address(lxon)).ORACLE_ROLE(), deployer);
        LXON(address(lxon)).grantRole(LXON(address(lxon)).MINT_ROLE(), address(psm));
        ERC20Mock(address(eurc)).mint(address(psm), 1000000 * 10**6);
        ERC20Mock(address(eurc)).approve(address(psm), 1000000 * 10**6);
        LXON(address(lxon)).updateCeiling(2000000000, bytes32(0));
        LXON(address(lxon)).mint(address(pair), 1000000000, bytes32(0));
        LXON(address(lxon)).mint(0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3, 10000000, bytes32(0));
        LXON(address(lxon)).mint(deployer, 1000000, bytes32(0));
        vm.stopBroadcast();

        vm.deal(deployer, 10000 ether);
        vm.startBroadcast(deployer);
        IERC20(address(weth)).approve(address(router), 5560 * 10**18);
        weth.deposit{value: 5560 ether}(deployer);
        IERC20(address(weth)).transfer(address(pair), 5560 * 10**18);
        pair.mint(deployer);
        vm.stopBroadcast();
    }
}
