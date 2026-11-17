import { exec } from "child_process";
import { promisify } from "util";

const execAsync = promisify(exec);

async function runMainnetTest() {
  console.log("🚀 Starting Comprehensive Mainnet Deployment Test - Chain ID 724\n");
  console.log("═".repeat(70));

  try {
    // Test 1: Network Configuration
    console.log("\n📡 Testing Network Configuration...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '1. Network Configuration'");
    console.log("✅ Network Configuration Tests Passed");

    // Test 2: Smart Contract Deployment
    console.log("\n📦 Testing Smart Contract Deployment...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '2. Smart Contract Deployment'");
    console.log("✅ Smart Contract Deployment Tests Passed");

    // Test 3: LXON Token Functionality
    console.log("\n💰 Testing LXON Token Functionality...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '3. LXON Token Functionality'");
    console.log("✅ LXON Token Functionality Tests Passed");

    // Test 4: Buyback Contract Configuration
    console.log("\n🔥 Testing Buyback Contract Configuration...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '4. Buyback Contract Configuration'");
    console.log("✅ Buyback Contract Configuration Tests Passed");

    // Test 5: USDC Token Configuration
    console.log("\n💵 Testing USDC Token Configuration...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '5. USDC Token Configuration'");
    console.log("✅ USDC Token Configuration Tests Passed");

    // Test 6: RPC Connectivity
    console.log("\n🌐 Testing RPC Connectivity...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '6. RPC Connectivity'");
    console.log("✅ RPC Connectivity Tests Passed");

    // Test 7: Contract Interaction Tests
    console.log("\n🔄 Testing Contract Interactions...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '7. Contract Interaction Tests'");
    console.log("✅ Contract Interaction Tests Passed");

    // Test 8: Chainlist Configuration
    console.log("\n📋 Testing Chainlist Configuration...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '8. Chainlist Configuration'");
    console.log("✅ Chainlist Configuration Tests Passed");

    // Test 9: Deployment Records
    console.log("\n📄 Testing Deployment Records...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '9. Deployment Records'");
    console.log("✅ Deployment Records Tests Passed");

    // Test 10: Integration Tests
    console.log("\n🔗 Testing Integration...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '10. Integration Tests'");
    console.log("✅ Integration Tests Passed");

    // Test 11: Security Configuration
    console.log("\n🔒 Testing Security Configuration...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '11. Security Configuration'");
    console.log("✅ Security Configuration Tests Passed");

    // Test 12: Performance Tests
    console.log("\n⚡ Testing Performance...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '12. Performance Tests'");
    console.log("✅ Performance Tests Passed");

    // Test 13: Error Handling
    console.log("\n⚠️  Testing Error Handling...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '13. Error Handling'");
    console.log("✅ Error Handling Tests Passed");

    // Test 14: Gas Optimization
    console.log("\n⛽ Testing Gas Optimization...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '14. Gas Optimization'");
    console.log("✅ Gas Optimization Tests Passed");

    // Test 15: Final System Health Check
    console.log("\n🏥 Running Final System Health Check...");
    await execAsync("npx hardhat test test/mainnet/MainnetDeployment.test.ts --grep '15. Final System Health Check'");
    console.log("✅ Final System Health Check Passed");

    console.log("\n" + "═".repeat(70));
    console.log("🎉 ALL MAINNET DEPLOYMENT TESTS PASSED!");
    console.log("═".repeat(70));
    console.log("\n📊 Test Summary:");
    console.log("  ✅ Network Configuration");
    console.log("  ✅ Smart Contract Deployment");
    console.log("  ✅ LXON Token Functionality");
    console.log("  ✅ Buyback Contract Configuration");
    console.log("  ✅ USDC Token Configuration");
    console.log("  ✅ RPC Connectivity");
    console.log("  ✅ Contract Interactions");
    console.log("  ✅ Chainlist Configuration");
    console.log("  ✅ Deployment Records");
    console.log("  ✅ Integration Tests");
    console.log("  ✅ Security Configuration");
    console.log("  ✅ Performance Tests");
    console.log("  ✅ Error Handling");
    console.log("  ✅ Gas Optimization");
    console.log("  ✅ System Health Check");
    console.log("\n🔗 Mainnet Deployment Status: READY FOR PRODUCTION");
    console.log("🌐 Domain: https://www.lxon.in");
    console.log("📡 RPC: https://www.lxon.in");
    console.log("⛓ Chain ID: 724");
    console.log("\n");

  } catch (error) {
    console.error("\n❌ Mainnet Deployment Test Failed:");
    console.error(error);
    process.exit(1);
  }
}

runMainnetTest().catch((error) => {
  console.error("❌ Test execution error:", error);
  process.exit(1);
});