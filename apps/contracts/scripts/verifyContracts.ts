import { ethers } from "hardhat";

async function main() {
  console.log("=== Verifying LXON Contracts on Explorer ===\n");

  const contracts = {
    WETH: "0x007696cdF0Bf860823126D72C8e3D52448B5285E",
    LXON: "0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E",
    Pair: "0x348E520f45dDd21EC927d7b14aB76cB2cd93DE08",
    Router: "0xA2AF542999c4412E387ba7e3867cE541cdfeDb80",
  };

  console.log("Contracts to verify:");
  console.log("- WETH:", contracts.WETH);
  console.log("- LXON:", contracts.LXON);
  console.log("- Pair:", contracts.Pair);
  console.log("- Router:", contracts.Router);
  console.log();

  // Note: This script requires the explorer to support contract verification
  // For Blockscout-based explorers, you can use the verification API directly
  // or use the hardhat-verify plugin with custom chain configuration

  console.log("=== Verification Instructions ===\n");
  console.log("1. Ensure your hardhat.config.ts has the customChains configuration for LXON");
  console.log("2. Set LXON_EXPLORER_API_KEY in your .env file (if required)");
  console.log("3. Run verification commands for each contract:\n");

  console.log("=== Manual Verification Commands ===\n");

  console.log("Verify WETH:");
  console.log(`npx hardhat verify --network lxon ${contracts.WETH}`);
  console.log();

  console.log("Verify LXON:");
  console.log(`npx hardhat verify --network lxon ${contracts.LXON}`);
  console.log();

  console.log("Verify Pair:");
  console.log(`npx hardhat verify --network lxon ${contracts.Pair} ${contracts.WETH} ${contracts.LXON}`);
  console.log();

  console.log("Verify Router:");
  console.log(`npx hardhat verify --network lxon ${contracts.Router} ${contracts.Pair}`);
  console.log();

  console.log("=== Alternative: Blockscout Manual Verification ===\n");
  console.log("If hardhat-verify doesn't work with your explorer:");
  console.log("1. Go to https://explorer.lxon.in");
  console.log("2. Search for each contract address");
  console.log("3. Click 'Verify and Publish' button");
  console.log("4. Upload the flattened contract source code");
  console.log("5. Provide constructor arguments (if any)");
  console.log("6. Submit for verification");
  console.log();

  console.log("=== Flattening Contracts ===\n");
  console.log("To flatten contracts for manual verification:");
  console.log("npx hardhat flatten contracts/WETH.sol > flattened/WETH flattened.sol");
  console.log("npx hardhat flatten contracts/LXON.sol > flattened/LXON flattened.sol");
  console.log("npx hardhat flatten contracts/UniswapV2Pair.sol > flattened/Pair flattened.sol");
  console.log("npx hardhat flatten contracts/UniswapV2Router.sol > flattened/Router flattened.sol");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
