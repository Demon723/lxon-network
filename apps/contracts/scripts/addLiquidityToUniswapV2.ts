import { ethers } from "hardhat";
import { WETH9, LXON } from "../typechain-types";

async function main() {
  const deployerAddress = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27";
  const deployer = await ethers.getSigner(deployerAddress);

  console.log("Adding liquidity to Uniswap V2 for $1.50 price");
  console.log("Account:", deployerAddress);

  // LXON contract address
  const LXON_ADDRESS = "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E";
  
  // Uniswap V2 Router (Ethereum Mainnet)
  const UNISWAP_V2_ROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
  const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"; // WETH on Ethereum Mainnet

  // Connect to contracts
  const lxon = (await ethers.getContractAt("LXON", LXON_ADDRESS)) as LXON;
  
  // Get Uniswap V2 Router interface
  const routerAbi = [
    "function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB, uint liquidity)",
    "function factory() external view returns (address)"
  ];
  const router = await ethers.getContractAt(routerAbi, UNISWAP_V2_ROUTER);

  // Target price: $1.50 per LXON
  const TARGET_PRICE_USD = 1.5;
  const ETH_PRICE_USD = 3000;
  const TARGET_WETH_PER_LXON = TARGET_PRICE_USD / ETH_PRICE_USD;

  console.log("\n=== Price Target ===");
  console.log("Target price: $", TARGET_PRICE_USD, "per LXON");
  console.log("Target WETH per LXON:", TARGET_WETH_PER_LXON);

  // Check which network we're on
  const network = await ethers.provider.getNetwork();
  console.log("\n=== Network ===");
  console.log("Chain ID:", network.chainId);
  console.log("Network name:", network.name);

  if (network.chainId !== 1n) {
    console.log("\n⚠️  WARNING: Uniswap V2 Router is for Ethereum Mainnet (Chain ID 1)");
    console.log("Current network is not Ethereum Mainnet");
    console.log("Please deploy to Ethereum Mainnet or use a different DEX for this network");
    return;
  }

  // Check balances
  const lxonBalance = await lxon.balanceOf(deployerAddress);
  const ethBalance = await ethers.provider.getBalance(deployerAddress);

  console.log("\n=== Balances ===");
  console.log("LXON balance:", ethers.formatUnits(lxonBalance, 6));
  console.log("ETH balance:", ethers.formatEther(ethBalance));

  // Calculate liquidity amounts
  // Use all available LXON
  const LXON_AMOUNT = lxonBalance;
  const WETH_AMOUNT = ethers.parseEther(String(Number(ethers.formatUnits(LXON_AMOUNT, 6)) * TARGET_WETH_PER_LXON));

  console.log("\n=== Liquidity to Add ===");
  console.log("LXON amount:", ethers.formatUnits(LXON_AMOUNT, 6));
  console.log("WETH amount:", ethers.formatEther(WETH_AMOUNT));
  console.log("Expected price: $", TARGET_PRICE_USD, "per LXON");

  if (lxonBalance < LXON_AMOUNT) {
    console.log("Insufficient LXON balance");
    return;
  }

  if (ethBalance < WETH_AMOUNT) {
    console.log("Insufficient ETH balance. Need:", ethers.formatEther(WETH_AMOUNT));
    console.log("Current:", ethers.formatEther(ethBalance));
    console.log("You need to add more ETH to your account");
    return;
  }

  // Approve Uniswap V2 Router to spend LXON
  console.log("\n=== Approving Uniswap V2 Router ===");
  const approveTx = await lxon.approve(UNISWAP_V2_ROUTER, LXON_AMOUNT);
  await approveTx.wait();
  console.log("LXON approved");

  // Add liquidity to Uniswap V2
  console.log("\n=== Adding Liquidity to Uniswap V2 ===");
  const deadline = Math.floor(Date.now() / 1000) + 3600;
  
  const addLiquidityTx = await router.addLiquidity(
    LXON_ADDRESS,
    WETH_ADDRESS,
    LXON_AMOUNT,
    WETH_AMOUNT,
    LXON_AMOUNT * 95n / 100n,  // 5% slippage tolerance
    WETH_AMOUNT * 95n / 100n, // 5% slippage tolerance
    deployerAddress,
    deadline,
    { value: WETH_AMOUNT }
  );
  
  const receipt = await addLiquidityTx.wait();
  console.log("Liquidity added successfully!");
  console.log("Transaction hash:", receipt?.hash);
  console.log("Gas used:", receipt?.gasUsed.toString());

  console.log("\n=== Success ===");
  console.log("Liquidity added to Uniswap V2");
  console.log("Price should be approximately $1.50 per LXON");
  console.log("TVL: ~$", (Number(ethers.formatUnits(LXON_AMOUNT, 6)) * TARGET_PRICE_USD * 2).toFixed(2));
  console.log("\nYou can now use this liquidity for exchange listings!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
