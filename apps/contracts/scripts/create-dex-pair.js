const { ethers } = require("ethers");
const fs = require("fs");

// Contract addresses
const DEX_FACTORY = "0xd99d3d037B124AA1Ea153B3D601a29BC75872a06";
const UNIVERSAL_ROUTER = "0xC416AC6B446Adf791Ef83e6B0f7FF2dc708F247a";
const WETH = "0x4d857b3e030bA985c5D32611Ff69238975790Be7";
const LXON = "0x6f872Ac9bBDF58434b9976ea0f7e2F3f5b44dC35";

// ERC20 ABI
const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function name() view returns (string)",
  "function symbol() view returns (string)"
];

// DEX Factory ABI
const FACTORY_ABI = [
  "function createPair(address tokenA, address tokenB) external returns (address pair)",
  "function getPair(address tokenA, address tokenB) view returns (address)"
];

// Universal Router ABI
const ROUTER_ABI = [
  "function createPair(address tokenA, address tokenB) external returns (address pair)",
  "function addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) external returns (uint256 amountA, uint256 amountB, uint256 liquidity)"
];

async function main() {
  console.log("=== Creating DEX Pair and Adding Liquidity ===\n");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log("Deployer:", wallet.address);

  const balance = await provider.getBalance(wallet.address);
  console.log("Balance:", ethers.formatEther(balance), "LXON\n");

  // Get contracts
  const factory = new ethers.Contract(DEX_FACTORY, FACTORY_ABI, wallet);
  const router = new ethers.Contract(UNIVERSAL_ROUTER, ROUTER_ABI, wallet);
  const wethToken = new ethers.Contract(WETH, ERC20_ABI, wallet);
  const lxonToken = new ethers.Contract(LXON, ERC20_ABI, wallet);

  // Check if pair already exists
  console.log("=== Checking if pair exists ===");
  const existingPair = await factory.getPair(WETH, LXON);
  console.log("Existing pair:", existingPair);

  if (existingPair !== ethers.ZeroAddress) {
    console.log("⚠️  Pair already exists at:", existingPair);
    console.log("Skipping pair creation\n");
  } else {
    // Create pair
    console.log("\n=== Creating LXON/WETH pair ===");
    const createTx = await factory.createPair(WETH, LXON);
    console.log("Transaction:", createTx.hash);
    await createTx.wait();
    console.log("✅ Pair created");

    const pairAddress = await factory.getPair(WETH, LXON);
    console.log("Pair address:", pairAddress);
  }

  // Get final pair address
  const pairAddress = await factory.getPair(WETH, LXON);

  // Check token balances
  console.log("\n=== Checking token balances ===");
  const wethBalance = await wethToken.balanceOf(wallet.address);
  const lxonBalance = await lxonToken.balanceOf(wallet.address);

  console.log("WETH balance:", ethers.formatEther(wethBalance));
  console.log("LXON balance:", ethers.formatEther(lxonBalance));

  // Need to mint tokens for liquidity
  console.log("\n=== Need to mint tokens for liquidity ===");
  console.log("Both WETH and LXON have 0 balance");
  console.log("LXON token needs mint() function");
  console.log("This requires additional setup\n");

  // Save pair address
  const report = {
    factory: DEX_FACTORY,
    router: UNIVERSAL_ROUTER,
    weth: WETH,
    lxon: LXON,
    pair: pairAddress,
    wethBalance: wethBalance.toString(),
    lxonBalance: lxonBalance.toString(),
    timestamp: new Date().toISOString()
  };

  fs.writeFileSync(
    "/Users/adikamble/LXON/LXON/apps/contracts/deployments/dex-pair-created.json",
    JSON.stringify(report, null, 2)
  );

  console.log("✅ Pair address saved to deployments/dex-pair-created.json");
  console.log("\n=== Next Steps ===");
  console.log("1. Mint LXON tokens to deployer address");
  console.log("2. Wrap LXON to WETH");
  console.log("3. Add liquidity to the pair");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
