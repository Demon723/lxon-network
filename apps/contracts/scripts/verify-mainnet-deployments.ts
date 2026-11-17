import { ethers } from "hardhat";
import { writeFileSync } from "fs";

// Known contract addresses from deployment files
const CONTRACTS_TO_VERIFY = {
  // From 724-bridge.json
  bridgeValidatorRegistry: "0x05f0ac677248c01F7f130676DB4584dbCc22FcFe",
  lxonBridge: "0x38e0Fc3E0E32dBD89984DB12eF4B5349D420b30D",

  // From 724-multisig-registry.json
  multiSigValidatorRegistry: "0x4894A06a666c59ee6FA09Bb7bd6946177F72Cb8D",

  // From dex-factory-724.json
  dexFactory: "0xf8B86d766b718188458c6867576bec4D74866813",
  universalRouter: "0x942c922CB78e5463669aCD7a29a4c5CF7Dc4CC75",

  // From .env (current addresses)
  weth: "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4",
  lxon: "0xc0177883C0c662870855660495C697385FE040f5",
  pair: "0x3aD52bD5996f16C902225b0d9C111fafE6B77786",
  router: "0x643a62a5472Ba3fA3eAbc834E3058eF2aBD07602",

  // From bridge config (alternate addresses)
  wethAlt: "0x007696cdF0Bf860823126D72C8e3D52448B5285E",
  lxonAlt: "0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c",
};

async function verifyContract(address: string, name: string, provider: any) {
  try {
    const code = await provider.getCode(address);
    const isDeployed = code !== "0x" && code.length > 2;

    return {
      name,
      address,
      isDeployed,
      codeLength: code.length,
      status: isDeployed ? "✅ DEPLOYED" : "❌ NOT DEPLOYED"
    };
  } catch (error: any) {
    return {
      name,
      address,
      isDeployed: false,
      error: error.message,
      status: "❌ ERROR"
    };
  }
}

async function main() {
  console.log("=== LXON Mainnet Contract Verification ===\n");

  const provider = new ethers.JsonRpcProvider(process.env.LXON_RPC_URL || "https://rpc.lxon.in");

  // Verify network
  const network = await provider.getNetwork();
  console.log(`Network: ${network.name}`);
  console.log(`Chain ID: ${network.chainId.toString()}`);
  console.log(`RPC: ${process.env.LXON_RPC_URL || "https://rpc.lxon.in"}\n`);

  if (network.chainId !== 724n) {
    console.warn("⚠️  WARNING: Not on LXON mainnet (expected chain ID: 724)");
  }

  console.log("=== Verifying Contracts ===\n");

  const results: any[] = [];

  for (const [name, address] of Object.entries(CONTRACTS_TO_VERIFY)) {
    console.log(`Checking ${name} (${address})...`);
    const result = await verifyContract(address, name, provider);
    results.push(result);
    console.log(`  ${result.status}\n`);
  }

  // Generate report
  const deployed = results.filter(r => r.isDeployed);
  const notDeployed = results.filter(r => !r.isDeployed);

  console.log("=== Summary ===");
  console.log(`Total Contracts Checked: ${results.length}`);
  console.log(`Deployed: ${deployed.length}`);
  console.log(`Not Deployed: ${notDeployed.length}\n`);

  console.log("=== Deployed Contracts ===");
  deployed.forEach(r => {
    console.log(`✅ ${r.name}: ${r.address}`);
  });

  console.log("\n=== Not Deployed Contracts ===");
  notDeployed.forEach(r => {
    console.log(`❌ ${r.name}: ${r.address}`);
    if (r.error) {
      console.log(`   Error: ${r.error}`);
    }
  });

  // Save report
  const report = {
    network: {
      name: network.name,
      chainId: network.chainId.toString(),
      rpc: process.env.LXON_RPC_URL || "https://rpc.lxon.in"
    },
    summary: {
      total: results.length,
      deployed: deployed.length,
      notDeployed: notDeployed.length
    },
    contracts: results,
    timestamp: new Date().toISOString()
  };

  writeFileSync(
    "/Users/adikamble/LXON/LXON/apps/contracts/deployments/mainnet-verification-report.json",
    JSON.stringify(report, null, 2)
  );

  console.log("\n✅ Report saved to deployments/mainnet-verification-report.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
