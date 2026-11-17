const { ethers } = require("ethers");

async function main() {
  console.log("=== Checking LXON Explorer for Deployed Contracts ===\n");

  const provider = new ethers.JsonRpcProvider("https://rpc.lxon.in");

  // Get recent blocks to find contract deployments
  console.log("Checking recent blocks for contract deployments...\n");

  const latestBlock = await provider.getBlockNumber();
  console.log(`Latest block: ${latestBlock}\n`);

  // Check last 100 blocks for contract creation transactions
  const blocksToCheck = 100;
  let contractsFound = new Set();

  for (let i = 0; i < blocksToCheck; i++) {
    const blockNumber = latestBlock - i;
    const block = await provider.getBlock(blockNumber);

    if (block && block.transactions) {
      for (const txHash of block.transactions) {
        try {
          const tx = await provider.getTransaction(txHash);
          if (tx && tx.creates) {
            const contractAddress = tx.creates;
            contractsFound.add(contractAddress);
            console.log(`Found contract deployment in block ${blockNumber}: ${contractAddress}`);
          }
        } catch (error) {
          // Skip errors
        }
      }
    }
  }

  console.log(`\n=== Contracts found in last ${blocksToCheck} blocks: ${contractsFound.size} ===`);
  contractsFound.forEach(address => {
    console.log(`  ${address}`);
  });

  // Try to get more info about these contracts
  console.log("\n=== Getting contract details ===\n");
  for (const address of contractsFound) {
    try {
      const code = await provider.getCode(address);
      console.log(`${address}: ${code.length} bytes`);
    } catch (error) {
      console.log(`${address}: Error getting code`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
