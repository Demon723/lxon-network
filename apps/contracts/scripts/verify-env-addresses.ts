import { ethers } from "hardhat";

async function main() {
  console.log("🔍 Verifying .env Deployed Addresses on Chain...");

  const [signer] = await ethers.getSigners();
  console.log("Connected as:", signer.address);

  // Addresses from .env
  const addresses = {
    "WETH": process.env.WETH_ADDRESS,
    "LXON": process.env.LXON_ADDRESS,
    "PAIR": process.env.PAIR_ADDRESS,
    "ROUTER": process.env.ROUTER_ADDRESS,
    "WETH_NEW": process.env.WETH_NEW,
    "LXON_NEW": process.env.LXON_NEW,
    "DEX_FACTORY": process.env.DEX_FACTORY,
    "UNIVERSAL_ROUTER": process.env.UNIVERSAL_ROUTER,
    "BRIDGE_VALIDATOR_REGISTRY": process.env.BRIDGE_VALIDATOR_REGISTRY,
    "LXON_BRIDGE": process.env.LXON_BRIDGE,
    "MULTISIG_VALIDATOR_REGISTRY": process.env.MULTISIG_VALIDATOR_REGISTRY,
    "DEX_PAIR_NEW": process.env.DEX_PAIR_NEW,
    "WETH_MINTABLE": process.env.WETH_MINTABLE,
    "DEX_PAIR_2DOLLAR": process.env.DEX_PAIR_2DOLLAR,
    "LP_STAKING_ADDRESS": process.env.LP_STAKING_ADDRESS,
    "YIELD_FARM_ADDRESS": process.env.YIELD_FARM_ADDRESS,
    "USDC_ADDRESS": process.env.USDC_ADDRESS,
    "DEX_PAIR_USDC": process.env.DEX_PAIR_USDC,
    "UNIVERSAL_BRIDGE": process.env.UNIVERSAL_BRIDGE,
    "LXON_REDEMPTION": process.env.LXON_REDEMPTION,
    "LIMIT_ORDER_BOOK": process.env.LIMIT_ORDER_BOOK,
  };

  console.log("\nChecking .env addresses on-chain...\n");

  for (const [name, address] of Object.entries(addresses)) {
    if (!address) {
      console.log(`${name}: ⚠️  Not set in .env`);
      continue;
    }

    try {
      const code = await ethers.provider.getCode(address);
      if (code === "0x") {
        console.log(`${name}: ❌ No contract deployed at ${address}`);
      } else {
        console.log(`${name}: ✅ Contract deployed at ${address}`);
      }
    } catch (error) {
      console.log(`${name}: ⚠️  Error checking: ${error}`);
    }
  }

  console.log("\n✅ Verification complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
