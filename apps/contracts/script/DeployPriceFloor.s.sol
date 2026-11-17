// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PriceFloorMechanism} from "../contracts/PriceFloorMechanism.sol";
import {LXONPriceOracle} from "../contracts/LXONPriceOracle.sol";

contract DeployPriceFloor is Script {
    IERC20 public usdc;
    IERC20 public weth;
    IERC20 public lxon;
    address public router;
    address public pair;
    address public ethUsdFeed;
    address public lxonEthFeed;
    
    PriceFloorMechanism public priceFloor;
    LXONPriceOracle public oracle;
    
    address public deployer;
    
    // Recommended initial reserves for $1.50 price floor
    uint256 public constant INITIAL_USDC_RESERVES = 3_500_000 * 1e6; // $3.5M USDC
    uint256 public constant INITIAL_WETH_RESERVES = 875 * 1e18; // ~875 ETH (~$1.75M)
    uint256 public constant BUYBACK_BUDGET_USDC = 1_000_000 * 1e6; // $1M daily limit
    uint256 public constant BUYBACK_BUDGET_WETH = 500 * 1e18; // ~500 ETH daily limit

    function run() external {
        deployer = vm.envAddress("DEPLOYER");
        
        // Load deployed contract addresses
        usdc = IERC20(vm.envAddress("USDC_ADDRESS"));
        weth = IERC20(vm.envAddress("WETH_ADDRESS"));
        lxon = IERC20(vm.envAddress("LXON_ADDRESS"));
        router = vm.envAddress("ROUTER_ADDRESS");
        pair = vm.envAddress("PAIR_ADDRESS");
        ethUsdFeed = vm.envAddress("ETH_USD_FEED");
        lxonEthFeed = vm.envAddress("LXON_ETH_FEED");

        vm.startBroadcast(deployer);

        // Deploy Price Oracle
        oracle = new LXONPriceOracle(
            ethUsdFeed,
            lxonEthFeed,
            address(lxon),
            address(weth),
            pair,
            deployer
        );

        // Deploy Price Floor Mechanism
        priceFloor = new PriceFloorMechanism(
            address(usdc),
            address(weth),
            address(lxon),
            router,
            pair,
            address(oracle),
            deployer
        );

        // Set buyback budgets
        priceFloor.setBuybackBudget(BUYBACK_BUDGET_USDC, BUYBACK_BUDGET_WETH);
        
        // Set buyback limits
        priceFloor.setBuybackLimits(
            100_000 * 1e6,  // Max $100k per transaction
            BUYBACK_BUDGET_USDC  // Daily limit
        );

        // Add initial reserves (if deployer has funds)
        uint256 usdcBalance = usdc.balanceOf(deployer);
        uint256 wethBalance = weth.balanceOf(deployer);
        
        if (usdcBalance >= INITIAL_USDC_RESERVES) {
            usdc.approve(address(priceFloor), INITIAL_USDC_RESERVES);
            priceFloor.addReserves(INITIAL_USDC_RESERVES, 0);
        }
        
        if (wethBalance >= INITIAL_WETH_RESERVES) {
            weth.approve(address(priceFloor), INITIAL_WETH_RESERVES);
            priceFloor.addReserves(0, INITIAL_WETH_RESERVES);
        }

        vm.stopBroadcast();

        // Log deployment results
        //console.log("Price Floor Mechanism deployed at:", address(priceFloor));
        //console.log("Price Oracle deployed at:", address(oracle));
        //console.log("Price floor set at: $1.50 USD");
        
        (uint256 currentPrice, uint256 floorPrice, uint256 triggerPrice, bool needsDefense_, ) = 
            priceFloor.getPriceStatus();
        
        //console.log("Current LXON price:", currentPrice / 1e18, "USD");
        //console.log("Floor price:", floorPrice / 1e18, "USD");
        //console.log("Trigger price:", triggerPrice / 1e18, "USD");
        //console.log("Needs defense:", needsDefense_);
        
        (uint256 usdcReserves, uint256 wethReserves, , , , ) = 
            priceFloor.getReserveInfo();
        
        //console.log("USDC reserves:", usdcReserves / 1e6, "USDC");
        //console.log("WETH reserves:", wethReserves / 1e18, "ETH");
    }
}