const { ethers } = require("ethers");

async function main() {
  console.log("=== Token Import Helper ===\n");

  const provider = new ethers.JsonRpcProvider("https://rpc.lxon.in");
  
  const lxonAddress = "0xc0177883C0c662870855660495C697385FE040f5";
  const wethAddress = "0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c";

  const erc20ABI = [
    "function name() view returns (string)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
    "function totalSupply() view returns (uint256)"
  ];

  console.log("=== LXON Token ===");
  console.log("Address:", lxonAddress);
  
  try {
    const lxon = new ethers.Contract(lxonAddress, erc20ABI, provider);
    const name = await lxon.name();
    const symbol = await lxon.symbol();
    const decimals = await lxon.decimals();
    const totalSupply = await lxon.totalSupply();

    console.log("Name:", name);
    console.log("Symbol:", symbol);
    console.log("Decimals:", decimals);
    console.log("Total Supply:", ethers.formatUnits(totalSupply, decimals));
    console.log("✅ Token verified");
  } catch (error) {
    console.log("❌ Token not found or error:", error.message);
  }

  console.log("\n=== WETH Token ===");
  console.log("Address:", wethAddress);
  
  try {
    const weth = new ethers.Contract(wethAddress, erc20ABI, provider);
    const name = await weth.name();
    const symbol = await weth.symbol();
    const decimals = await weth.decimals();
    const totalSupply = await weth.totalSupply();

    console.log("Name:", name);
    console.log("Symbol:", symbol);
    console.log("Decimals:", decimals);
    console.log("Total Supply:", ethers.formatUnits(totalSupply, decimals));
    console.log("✅ Token verified");
  } catch (error) {
    console.log("❌ Token not found or error:", error.message);
  }

  console.log("\n=== MetaMask Import Links ===");
  console.log("\nLXON Token:");
  console.log("Contract: 0xc0177883C0c662870855660495C697385FE040f5");
  console.log("Symbol: LXON");
  console.log("Decimals: 6");
  console.log("\nManual Import Steps:");
  console.log("1. Open MetaMask");
  console.log("2. Scroll to bottom → Import Tokens");
  console.log("3. Custom Token");
  console.log("4. Paste contract address");
  console.log("5. Symbol: LXON");
  console.log("6. Decimals: 6");
  console.log("7. Add Custom Token");

  console.log("\nWETH Token:");
  console.log("Contract: 0x94DaB83AFE9b77c1ccf6c4963e530F22c928b92c");
  console.log("Symbol: WETH");
  console.log("Decimals: 18");
  console.log("\nManual Import Steps:");
  console.log("1. Open MetaMask");
  console.log("2. Scroll to bottom → Import Tokens");
  console.log("3. Custom Token");
  console.log("4. Paste contract address");
  console.log("5. Symbol: WETH");
  console.log("6. Decimals: 18");
  console.log("7. Add Custom Token");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
