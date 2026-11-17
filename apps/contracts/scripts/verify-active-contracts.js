const { ethers } = require("ethers");
const fs = require("fs");

// These are the addresses from .env that are currently in use
const ACTIVE_CONTRACTS = {
  weth: "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4",
  lxon: "0xc0177883C0c662870855660495C697385FE040f5",
  pair: "0x3aD52bD5996f16C902225b0d9C111fafE6B77786",
  router: "0x643a62a5472Ba3fA3eAbc834E3058eF2aBD07602",
};

async function getContractDetails(address, provider) {
  try {
    const code = await provider.getCode(address);
    if (code === "0x" || code.length <= 2) {
      return null;
    }

    // Try to get basic info
    const details = {
      address,
      codeLength: code.length,
      deployed: true
    };

    // Try to call common functions to identify contract type
    try {
      // Check if it's an ERC20
      const erc20 = new ethers.Contract(
        address,
        ["function name() view returns (string)", "function symbol() view returns (string)", "function decimals() view returns (uint8)", "function totalSupply() view returns (uint256)"],
        provider
      );

      try {
        details.name = await erc20.name();
        details.symbol = await erc20.symbol();
        const decimals = await erc20.decimals();
        details.decimals = Number(decimals);
        const totalSupply = await erc20.totalSupply();
        details.totalSupply = totalSupply.toString();
        details.type = "ERC20";
      } catch (e) {
        // Not an ERC20
      }
    } catch (e) {
      // Can't identify type
    }

    return details;
  } catch (error) {
    return {
      address,
      deployed: false,
      error: error.message
    };
  }
}

async function main() {
  console.log("=== LXON Mainnet Active Contract Verification ===\n");

  const provider = new ethers.JsonRpcProvider("https://rpc.lxon.in");

  // Verify network
  const network = await provider.getNetwork();
  console.log(`Network: ${network.name}`);
  console.log(`Chain ID: ${network.chainId.toString()}`);
  console.log(`RPC: https://rpc.lxon.in\n`);

  console.log("=== Verifying Active Contracts ===\n");

  const results = [];

  for (const [name, address] of Object.entries(ACTIVE_CONTRACTS)) {
    console.log(`Checking ${name} (${address})...`);
    const details = await getContractDetails(address, provider);
    results.push({ name, ...details });

    if (details.deployed) {
      console.log(`  ✅ DEPLOYED (${details.codeLength} bytes)`);
      if (details.type) {
        console.log(`  Type: ${details.type}`);
        console.log(`  Name: ${details.name}`);
        console.log(`  Symbol: ${details.symbol}`);
        console.log(`  Decimals: ${details.decimals}`);
        console.log(`  Total Supply: ${details.totalSupply}`);
      }
    } else {
      console.log(`  ❌ NOT DEPLOYED`);
      if (details.error) {
        console.log(`  Error: ${details.error}`);
      }
    }
    console.log();
  }

  // Save report
  const report = {
    network: {
      name: network.name,
      chainId: Number(network.chainId),
      rpc: "https://rpc.lxon.in"
    },
    contracts: results,
    timestamp: new Date().toISOString()
  };

  fs.writeFileSync(
    "/Users/adikamble/LXON/LXON/apps/contracts/deployments/active-contracts-report.json",
    JSON.stringify(report, null, 2)
  );

  console.log("✅ Report saved to deployments/active-contracts-report.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
