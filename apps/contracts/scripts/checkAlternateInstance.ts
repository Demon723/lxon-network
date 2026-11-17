import { ethers } from "hardhat";

async function main() {
  console.log("=== Checking Alternative LXON Instance ===\n");

  // Try the previously successful instance
  const altRPC = "http://13.51.158.120:8546";
  const currentRPC = "http://16.171.20.249:8545";

  console.log("Testing alternative instance:", altRPC);
  console.log("Testing current instance:", currentRPC);
  console.log();

  // Test alternative instance
  try {
    const altProvider = new ethers.JsonRpcProvider(altRPC);
    const altNetwork = await altProvider.getNetwork();
    const altBlockNumber = await altProvider.getBlockNumber();
    
    console.log("✅ Alternative Instance Response:");
    console.log("  Chain ID:", altNetwork.chainId.toString());
    console.log("  Block Number:", altBlockNumber);
    console.log("  Network Name:", altNetwork.name);
    
    if (altNetwork.chainId === 724n) {
      console.log("✅ Correct LXON network (Chain ID 724)");
    }
    
    // Check deployer balance
    const deployerAddress = "0x098Ae030804120Def93880a303788d24dc600d00";
    const balance = await altProvider.getBalance(deployerAddress);
    console.log("  Deployer balance:", ethers.formatEther(balance), "LXON");
    
    // Check for existing contracts
    const previousAddresses = {
      WETH: "0x4F90ddD66C2616DC8870F7f7B94b3e0247068ad4",
      LXON: "0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c",
      Pair: "0xac86E2dE13eAC876ED8872b76BBAa10e2c1050cC",
      Router: "0xEF4ce5C29dD14fE2A342F0BC38D5A1cEBD500e6C"
    };

    console.log("\n  Checking for existing contracts:");
    for (const [name, address] of Object.entries(previousAddresses)) {
      try {
        const code = await altProvider.getCode(address);
        if (code.length > 2) {
          console.log(`    ✅ ${name} exists at ${address}`);
        } else {
          console.log(`    ❌ ${name} NOT found at ${address}`);
        }
      } catch (error) {
        console.log(`    ⚠️ ${name} check error`);
      }
    }
    
    console.log("\n=== Alternative Instance Working! ===");
    console.log("Use this RPC instead:", altRPC);
    console.log("Update .env with: LXON_RPC_URL=http://13.51.158.120:8546");
    
  } catch (error) {
    console.log("❌ Alternative Instance Error:", error.message);
    console.log("Alternative instance may be offline");
  }

  console.log();

  // Test current instance
  try {
    const currentProvider = new ethers.JsonRpcProvider(currentRPC);
    const currentNetwork = await currentProvider.getNetwork();
    const currentBlockNumber = await currentProvider.getBlockNumber();
    
    console.log("✅ Current Instance Response:");
    console.log("  Chain ID:", currentNetwork.chainId.toString());
    console.log("  Block Number:", currentBlockNumber);
    console.log("  Network Name:", currentNetwork.name);
  } catch (error) {
    console.log("❌ Current Instance Error:", error.message);
  }

  console.log("\n=== Recommendation ===");
  console.log("If alternative instance (13.51.158.120) is working:");
  console.log("1. Update .env: LXON_RPC_URL=http://13.51.158.120:8546");
  console.log("2. Run: npm run verify:deployment");
  console.log("3. If contracts exist, add liquidity directly");
  console.log("4. If contracts don't exist, deploy fresh contracts");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });