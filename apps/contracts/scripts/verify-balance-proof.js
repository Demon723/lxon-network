const { ethers } = require("ethers");
const fs = require("fs");

async function main() {
  const filename = process.argv[2];

  if (!filename) {
    console.log("Usage: node verify-balance-proof.js <proof-file>");
    process.exit(1);
  }

  console.log("=== Verify Balance Proof ===\n");

  const proof = JSON.parse(fs.readFileSync(filename, "utf8"));

  console.log("Wallet:", proof.wallet);
  console.log("Token:", proof.token);
  console.log("Balance:", proof.balance);
  console.log("Block:", proof.blockNumber);

  // Verify signature
  const message = proof.message;
  const signerAddress = ethers.verifyMessage(message, proof.signature);

  console.log("\n=== Signature Verification ===");
  console.log("Message:", message);
  console.log("Signature:", proof.signature);
  console.log("Recovered Address:", signerAddress);
  console.log("Expected Address:", proof.wallet);
  console.log("Signature Valid:", signerAddress.toLowerCase() === proof.wallet.toLowerCase());

  // Verify EIP-712 signature
  const recoveredEIP712 = ethers.verifyTypedData(
    proof.eip712.domain,
    proof.eip712.types,
    proof.eip712.value,
    proof.eip712.signature
  );

  console.log("\n=== EIP-712 Verification ===");
  console.log("Recovered Address:", recoveredEIP712);
  console.log("Expected Address:", proof.wallet);
  console.log("EIP-712 Valid:", recoveredEIP712.toLowerCase() === proof.wallet.toLowerCase());

  // Verify on-chain
  const provider = new ethers.JsonRpcProvider("https://rpc.lxon.in");
  const lxon = new ethers.Contract(proof.tokenAddress, ["function balanceOf(address) view returns (uint256)"], provider);
  const currentBalance = await lxon.balanceOf(proof.wallet);
  const decimals = await lxon.decimals();
  const currentBalanceFormatted = ethers.formatUnits(currentBalance, decimals);

  console.log("\n=== On-Chain Verification ===");
  console.log("Balance at Proof Time:", proof.balance);
  console.log("Current Balance:", currentBalanceFormatted);
  console.log("Balance Changed:", currentBalanceFormatted !== proof.balance);

  const currentBlock = await provider.getBlockNumber();
  console.log("Block at Proof Time:", proof.blockNumber);
  console.log("Current Block:", currentBlock);
  console.log("Blocks Since Proof:", currentBlock - proof.blockNumber);

  console.log("\n=== Verification Result ===");
  const signatureValid = signerAddress.toLowerCase() === proof.wallet.toLowerCase();
  const eip712Valid = recoveredEIP712.toLowerCase() === proof.wallet.toLowerCase();

  if (signatureValid && eip712Valid) {
    console.log("✅ Signature verification PASSED");
  } else {
    console.log("❌ Signature verification FAILED");
  }

  if (currentBalanceFormatted === proof.balance) {
    console.log("✅ Balance verification PASSED");
  } else {
    console.log("⚠️  Balance changed since proof");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
