const { ethers } = require("ethers");
const fs = require("fs");

// New deployed addresses
const NEW_CONTRACTS = {
  weth: "0x4d857b3e030bA985c5D32611Ff69238975790Be7",
  lxon: "0x6f872Ac9bBDF58434b9976ea0f7e2F3f5b44dC35",
  dexFactory: "0xd99d3d037B124AA1Ea153B3D601a29BC75872a06",
  universalRouter: "0xC416AC6B446Adf791Ef83e6B0f7FF2dc708F247a",
  bridgeValidatorRegistry: "0x4FDa2fC19249F6193b19338639fc161345EB97ff",
  lxonBridge: "0xfDC175150714C7663D626Dd551f829b1Ba748877",
  multiSigValidatorRegistry: "0x69e08b01b769Ec63944473Fa5AdAc4784fAd6Fb3"
};

async function verifyContract(address, name, provider) {
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
  } catch (error) {
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
  console.log("=== Verifying Newly Deployed Contracts ===\n");

  const provider = new ethers.JsonRpcProvider("https://rpc.lxon.in");

  const network = await provider.getNetwork();
  console.log(`Network: ${network.name}`);
  console.log(`Chain ID: ${network.chainId.toString()}`);
  console.log(`RPC: https://rpc.lxon.in\n`);

  console.log("=== Verifying Contracts ===\n");

  const results = [];

  for (const [name, address] of Object.entries(NEW_CONTRACTS)) {
    console.log(`Checking ${name} (${address})...`);
    const result = await verifyContract(address, name, provider);
    results.push(result);
    console.log(`  ${result.status}\n`);
  }

  const deployed = results.filter(r => r.isDeployed);
  const notDeployed = results.filter(r => !r.isDeployed);

  console.log("=== Summary ===");
  console.log(`Total Contracts Checked: ${results.length}`);
  console.log(`Deployed: ${deployed.length}`);
  console.log(`Not Deployed: ${notDeployed.length}\n`);

  console.log("=== Deployed Contracts ===");
  deployed.forEach(r => {
    console.log(`✅ ${r.name}: ${r.address} (${r.codeLength} bytes)`);
  });

  console.log("\n=== Not Deployed Contracts ===");
  notDeployed.forEach(r => {
    console.log(`❌ ${r.name}: ${r.address}`);
    if (r.error) {
      console.log(`   Error: ${r.error}`);
    }
  });

  const report = {
    network: {
      name: network.name,
      chainId: network.chainId.toString(),
      rpc: "https://rpc.lxon.in"
    },
    summary: {
      total: results.length,
      deployed: deployed.length,
      notDeployed: notDeployed.length
    },
    contracts: results,
    timestamp: new Date().toISOString()
  };

  fs.writeFileSync(
    "/Users/adikamble/LXON/LXON/apps/contracts/deployments/new-deployments-verification.json",
    JSON.stringify(report, null, 2)
  );

  console.log("\n✅ Report saved to deployments/new-deployments-verification.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
