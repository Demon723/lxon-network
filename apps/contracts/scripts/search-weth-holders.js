const { ethers } = require("ethers");
require("dotenv").config();

const WETH_ADDRESS = "0x86a7da576852126c8421F7a25F8dE7cEDF9553C4";
const LXON_RPC_URL = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

const WETH_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)"
];

async function main() {
  console.log("=== Search for Large WETH Holders ===\n");

  const provider = new ethers.JsonRpcProvider(LXON_RPC_URL);
  const weth = new ethers.Contract(WETH_ADDRESS, WETH_ABI, provider);

  // All known addresses
  const addresses = [
    "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27", // Deployer
    "0x7999b8C0662FE6aE3d82Ac6988718189E66f9B4b", // 1B LXON address
    "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3", // Founder
    "0x098Ae030804120Def93880a303788d24dc600d00", // Earlier owner
    "0x3aD52bD5996f16C902225b0d9C111fafE6B77786", // DEX Pair
    "0x643a62a5472Ba3fAeAbc834E3058eF2aBD07602", // Router
    "0xd99d3d037B124AA1Ea153B3D601a29BC75872a06", // New Factory
    "0xC416AC6B446Adf791Ef83e6B0f7FF2dc708F247a", // Universal Router
    "0x4FDa2fC19249F6193b19338639fc161345EB97ff", // Bridge Validator Registry
    "0xfDC175150714C7663D626Dd551f829b1Ba748877", // LXON Bridge
    "0x69e08b01b769Ec63944473Fa5AdAc4784fAd6Fb3", // MultiSig Validator Registry
    "0x6a4c5e73e6A075f96391fDC0a164D52804cA0519", // New DEX Pair
    "0xc0177883C0c662870855660495C697385FE040f5", // LXON
    "0x4d857b3e030bA985c5D32611Ff69238975790Be7", // New WETH
    "0x6f872Ac9bBDF58434b9976ea0f7e2F3f5b44dC35", // New LXON
  ];

  const wethDecimals = await weth.decimals();
  const totalSupply = await weth.totalSupply();

  console.log("WETH Total Supply:", ethers.formatUnits(totalSupply, wethDecimals));
  console.log("\nChecking WETH balances across all known addresses...\n");

  let totalWeth = 0n;
  let largestHolder = { address: null, balance: 0n };

  for (const address of addresses) {
    try {
      const balance = await weth.balanceOf(address);
      totalWeth += balance;

      if (balance > largestHolder.balance) {
        largestHolder = { address, balance };
      }

      console.log(`${address}: ${ethers.formatUnits(balance, wethDecimals)} WETH`);
    } catch (error) {
      console.log(`${address}: Error checking balance`);
    }
  }

  console.log("\n=== Summary ===");
  console.log("Total WETH across all known addresses:", ethers.formatUnits(totalWeth, wethDecimals));
  console.log("Largest holder:", largestHolder.address);
  console.log("Largest holder balance:", ethers.formatUnits(largestHolder.balance, wethDecimals));

  console.log("\n=== Target ===");
  console.log("Needed for $2/LXON: 111,600,000 WETH");
  console.log("Total available:", ethers.formatUnits(totalWeth, wethDecimals));
  console.log("Short by:", (111600000 - Number(ethers.formatUnits(totalWeth, wethDecimals))).toFixed(0));

  if (Number(ethers.formatUnits(totalWeth, wethDecimals)) < 111600000) {
    console.log("\n❌ Insufficient WETH in known addresses");
    console.log("No one in the known ecosystem has 111.6M WETH");
    console.log("\n=== Options ===");
    console.log("1. Find unknown addresses outside the ecosystem (very unlikely)");
    console.log("2. Buy WETH from someone who has it (unknown if anyone has that much)");
    console.log("3. Wrap more native LXON (only have ~19.3M available)");
    console.log("4. Accept current price of $0.257/LXON");
  } else {
    console.log("\n✅ Sufficient WETH found!");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
