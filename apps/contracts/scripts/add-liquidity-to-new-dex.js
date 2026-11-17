const { ethers } = require("ethers");
const fs = require("fs");

// NEW DEX addresses (deployed today)
const NEW_FACTORY = "0xd99d3d037B124AA1Ea153B3D601a29BC75872a06";
const NEW_ROUTER = "0xC416AC6B446Adf791Ef83e6B0f7FF2dc708F247a";
const NEW_PAIR = "0x6a4c5e73e6A075f96391fDC0a164D52804cA0519";

// Original token addresses (have balances)
const ORIGINAL_WETH = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const ORIGINAL_LXON = "0xc0177883C0c662870855660495C697385FE040f5";

// Wallet that has the WETH balance
const WETH_HOLDER = "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b"; // Your wallet with 2,326 WETH

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) external returns (bool)",
  "function decimals() view returns (uint8)",
  "function name() view returns (string)",
  "function symbol() view returns (string)"
];

const PAIR_ABI = [
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function mint(address to) external returns (uint256 liquidity)",
  "function balanceOf(address) view returns (uint256)"
];

async function main() {
  console.log("=== Adding Liquidity to NEW DEX ===\n");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log("Deployer:", wallet.address);

  // Get token contracts
  const wethToken = new ethers.Contract(ORIGINAL_WETH, ERC20_ABI, provider);
  const lxonToken = new ethers.Contract(ORIGINAL_LXON, ERC20_ABI, provider);
  const newPair = new ethers.Contract(NEW_PAIR, PAIR_ABI, wallet);

  // Check balances
  console.log("\n=== Checking WETH Holder Balance ===");
  const holderWethBalance = await wethToken.balanceOf(WETH_HOLDER);
  console.log("WETH holder:", WETH_HOLDER);
  console.log("WETH balance:", ethers.formatEther(holderWethBalance));

  const holderLxonBalance = await lxonToken.balanceOf(WETH_HOLDER);
  console.log("LXON balance:", ethers.formatEther(holderLxonBalance));

  if (holderWethBalance === 0n) {
    console.log("\n❌ WETH holder has no WETH balance");
    console.log("Cannot add liquidity");
    return;
  }

  // Ask user how much to add
  const WETH_TO_ADD = ethers.parseEther("100"); // Add 100 WETH
  const LXON_TO_ADD = ethers.parseEther("100"); // Add 100 LXON (assumes 1:1)

  console.log("\n=== Amounts to Add ===");
  console.log("WETH:", ethers.formatEther(WETH_TO_ADD));
  console.log("LXON:", ethers.formatEther(LXON_TO_ADD));

  if (holderWethBalance < WETH_TO_ADD) {
    console.log("\n⚠️  Insufficient WETH balance for 100 WETH");
    console.log("Using available balance instead");
    const wethToUse = holderWethBalance;
    console.log("Will add:", ethers.formatEther(wethToUse), "WETH");
  }

  // Need to use WETH holder's private key to transfer
  console.log("\n⚠️  NEED WETH HOLDER PRIVATE KEY");
  console.log("Current deployer does not have WETH");
  console.log("WETH is in wallet:", WETH_HOLDER);
  console.log("\nPlease provide WETH_HOLDER_PRIVATE_KEY in .env or");
  console.log("Transfer WETH to deployer first, then run this script again");

  // Alternative: Create script to transfer WETH from holder to deployer
  console.log("\n=== Alternative: Transfer WETH to Deployer ===");
  console.log("I can create a script to transfer WETH from holder to deployer");
  console.log("Then add liquidity using deployer's balance");

  // Save configuration
  const config = {
    newFactory: NEW_FACTORY,
    newRouter: NEW_ROUTER,
    newPair: NEW_PAIR,
    originalWeth: ORIGINAL_WETH,
    originalLxon: ORIGINAL_LXON,
    wethHolder: WETH_HOLDER,
    holderWethBalance: holderWethBalance.toString(),
    holderLxonBalance: holderLxonBalance.toString(),
    suggestedWethToAdd: WETH_TO_ADD.toString(),
    suggestedLxonToAdd: LXON_TO_ADD.toString(),
    timestamp: new Date().toISOString()
  };

  fs.writeFileSync(
    "/Users/adikamble/LXON/LXON/apps/contracts/deployments/new-dex-liquidity-config.json",
    JSON.stringify(config, null, 2)
  );

  console.log("\n✅ Configuration saved to deployments/new-dex-liquidity-config.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
