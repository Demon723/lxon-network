const { ethers } = require("ethers");

const BRIDGE_ADDRESS = "0xfDC175150714C7663D626Dd551f829b1Ba748877";

const BRIDGE_ABI = [
  "function chainId() view returns (uint256)",
  "function validatorRegistry() view returns (address)",
  "function admin() view returns (address)",
  "function weth() view returns (address)",
  "function timelock() view returns (address)",
  "function setTokenConfig(address token, uint8 mode, bool enabled, uint256 minAmount, uint256 maxAmount, uint256 dailyLimit) external"
];

async function main() {
  console.log("=== Checking Bridge State ===\n");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log("Deployer address:", wallet.address);

  const bridge = new ethers.Contract(BRIDGE_ADDRESS, BRIDGE_ABI, provider);

  const chainId = await bridge.chainId();
  const validatorRegistry = await bridge.validatorRegistry();
  const admin = await bridge.admin();
  const weth = await bridge.weth();
  const timelock = await bridge.timelock();

  console.log("\n=== Bridge Configuration ===");
  console.log("Chain ID:", chainId.toString());
  console.log("Validator Registry:", validatorRegistry);
  console.log("Admin:", admin);
  console.log("WETH:", weth);
  console.log("Timelock:", timelock);
  console.log("\n=== Access Check ===");
  console.log("Deployer address:", wallet.address);
  console.log("Timelock address:", timelock);
  console.log("Deployer == Timelock?", wallet.address.toLowerCase() === timelock.toLowerCase());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
