// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WETH9} from "../contracts/WETH.sol";
import {LXON} from "../contracts/LXON.sol";
import {Pair} from "../contracts/Pair.sol";
import {Router} from "../contracts/Router.sol";

contract AddInitialLiquidity is Script {
    WETH9 public weth;
    LXON public lxon;
    Pair public pair;
    Router public router;
    address public deployer;

    uint256 public constant INITIAL_LXON = 1000 * 10**18; // 1000 LXON
    uint256 public constant INITIAL_WETH = 1000 * 10**18; // 1000 WETH

    function run() external {
        deployer = vm.envAddress("DEPLOYER");
        
        // Load deployed contract addresses from environment or use hardcoded values
        address wethAddress = vm.envAddress("WETH_ADDRESS");
        address lxonAddress = vm.envAddress("LXON_ADDRESS");
        address pairAddress = vm.envAddress("PAIR_ADDRESS");
        address routerAddress = vm.envAddress("ROUTER_ADDRESS");

        weth = WETH9(wethAddress);
        lxon = LXON(lxonAddress);
        pair = Pair(pairAddress);
        router = Router(routerAddress);

        vm.startBroadcast(deployer);

        // Mint initial LXON to deployer if needed
        bytes32 MINT_ROLE = keccak256("MINT_ROLE");
        if (lxon.hasRole(MINT_ROLE, deployer)) {
            lxon.mint(deployer, INITIAL_LXON, bytes32(0));
        }

        // Deposit ETH to get WETH
        weth.deposit{value: INITIAL_WETH}();

        // Approve router to spend tokens
        IERC20(address(lxon)).approve(address(router), INITIAL_LXON);
        IERC20(address(weth)).approve(address(router), INITIAL_WETH);

        // Add initial liquidity
        router.addLiquidity(
            INITIAL_LXON,
            INITIAL_WETH,
            INITIAL_LXON,  // amountLXONMin
            INITIAL_WETH, // amountWLXONMin
            deployer,     // to
            block.timestamp + 1 days
        );

        vm.stopBroadcast();

        // Log results
        uint256 lpBalance = pair.balanceOf(deployer);
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        
        // //console.log("Initial liquidity added successfully!");
        // //console.log("LP tokens received:", lpBalance);
        // //console.log("LXON reserves:", reserve0);
        // //console.log("WETH reserves:", reserve1);
    }
}