const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Deploy LxonLimitOrderBook ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const lxonAddress = process.env.LXON_ADDRESS;
  const usdcAddress = process.env.USDC_ADDRESS;
  const pairAddress = process.env.DEX_PAIR_USDC;
  const owner = deployer.address;

  console.log("LXON Address:", lxonAddress);
  console.log("USDC Address:", usdcAddress);
  console.log("Pair Address:", pairAddress);
  console.log("Owner:", owner);

  const LimitOrderBook = await ethers.getContractFactory("LxonLimitOrderBook");
  const limitOrderBook = await LimitOrderBook.deploy(
    lxonAddress,
    usdcAddress,
    pairAddress,
    owner
  );
  await limitOrderBook.waitForDeployment();
  const limitOrderBookAddress = await limitOrderBook.getAddress();

  console.log("\n✅ LxonLimitOrderBook deployed to:", limitOrderBookAddress);

  console.log("\n=== Features ===");
  console.log("✅ Create limit orders");
  console.log("✅ Fill limit orders");
  console.log("✅ Cancel limit orders");
  console.log("✅ View user orders");
  console.log("✅ Buy/Sell LXON at desired price");

  console.log("\n=== Update .env ===");
  console.log("Add this line to .env:");
  console.log(`LIMIT_ORDER_BOOK=${limitOrderBookAddress}`);

  console.log("\n=== Next Steps ===");
  console.log("1. Add limit order UI to trading interface");
  console.log("2. Test order creation and filling");
  console.log("3. Deploy lending protocol");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
