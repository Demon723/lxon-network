const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("=== Balance Proof Generator ===\n");

  const lxonAddress = process.env.LXON_ADDRESS;

  const provider = new ethers.JsonRpcProvider("https://rpc.lxon.in");
  const wallet = new ethers.Wallet(process.env.YOUR_WALLET_PRIVATE_KEY, provider);
  const walletAddress = wallet.address;

  console.log("Wallet Address:", walletAddress);
  console.log("LXON Address:", lxonAddress);

  const lxonABI = [
    "function balanceOf(address) view returns (uint256)",
    "function decimals() view returns (uint8)",
    "function symbol() view returns (string)"
  ];

  const lxon = new ethers.Contract(lxonAddress, lxonABI, provider);
  const balance = await lxon.balanceOf(walletAddress);
  const decimals = await lxon.decimals();
  const symbol = await lxon.symbol();

  const balanceFormatted = ethers.formatUnits(balance, decimals);
  const blockNumber = await provider.getBlockNumber();
  const block = await provider.getBlock(blockNumber);
  const timestamp = new Date(block.timestamp * 1000).toISOString();

  console.log("\n=== Balance Information ===");
  console.log("Token:", symbol);
  console.log("Balance:", balanceFormatted);
  console.log("Raw Balance:", balance.toString());
  console.log("Block Number:", blockNumber);
  console.log("Block Timestamp:", timestamp);

  // Generate signed message
  const message = `I own ${balanceFormatted} ${symbol} in wallet ${walletAddress} at block ${blockNumber}`;
  const signature = await wallet.signMessage(message);

  console.log("\n=== Signed Message ===");
  console.log("Message:", message);
  console.log("Signature:", signature);

  // Generate EIP-712 typed data
  const domain = {
    name: "LXON Balance Proof",
    version: "1",
    chainId: 724,
    verifyingContract: lxonAddress
  };

  const types = {
    BalanceProof: [
      { name: "wallet", type: "address" },
      { name: "balance", type: "uint256" },
      { name: "blockNumber", type: "uint256" }
    ]
  };

  const value = {
    wallet: walletAddress,
    balance: balance.toString(),
    blockNumber: blockNumber
  };

  const eip712Signature = await wallet.signTypedData(domain, types, value);

  console.log("\n=== EIP-712 Typed Data ===");
  console.log("Domain:", JSON.stringify(domain, null, 2));
  console.log("Types:", JSON.stringify(types, null, 2));
  console.log("Value:", JSON.stringify(value, null, 2));
  console.log("Signature:", eip712Signature);

  // Generate proof document
  const proof = {
    wallet: walletAddress,
    token: symbol,
    tokenAddress: lxonAddress,
    balance: balanceFormatted,
    rawBalance: balance.toString(),
    blockNumber: blockNumber,
    timestamp: timestamp,
    message: message,
    signature: signature,
    eip712: {
      domain,
      types,
      value,
      signature: eip712Signature
    }
  };

  console.log("\n=== Complete Proof ===");
  console.log(JSON.stringify(proof, null, 2));

  // Save to file
  const fs = require("fs");
  const filename = `balance-proof-${Date.now()}.json`;
  fs.writeFileSync(filename, JSON.stringify(proof, null, 2));
  console.log("\n✅ Proof saved to:", filename);

  // Generate verification instructions
  console.log("\n=== Verification Instructions ===");
  console.log("1. Check balance on block explorer:");
  console.log(`   https://explorer.lxon.in/address/${walletAddress}`);
  console.log("\n2. Verify signature:");
  console.log("   Use ethers.js to recover signer from signature");
  console.log("\n3. Verify block:");
  console.log("   Check block number and timestamp");
  console.log("\n4. Verify token:");
  console.log("   Confirm token address matches LXON contract");

  console.log("\n=== Verification Script ===");
  console.log("Run this to verify the proof:");
  console.log(`node scripts/verify-balance-proof.js ${filename}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
