import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🔄 Initiating Cross-Chain Transfer: LXON from LXON to Sepolia");
  console.log("");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY || process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("No private key found in environment variables");
  }

  const signer = new ethers.Wallet(privateKey, ethers.provider);
  console.log("Sender address:", signer.address);

  // Contract addresses
  const lxonBridgeAddress = "0x692D0047323034514686eF57edFC26DBBa53F87B";
  const lxonTokenAddress = "0xc0177883C0c662870855660495C697385FE040f5";
  const sepoliaChainId = 11155111; // Sepolia Testnet

  // Connect to contracts
  const lxonBridge = await ethers.getContractAt("LxonBridgeMultiSig", lxonBridgeAddress);
  const lxonToken = await ethers.getContractAt("LXONNativeTokenEnhanced", lxonTokenAddress);

  // Check LXON balance
  console.log("Checking LXON balance...");
  const balance = await lxonToken.balanceOf(signer.address);
  console.log("LXON balance:", ethers.formatUnits(balance, 6), "LXON");

  if (balance === 0n) {
    console.log("❌ No LXON balance available.");
    return;
  }

  // Transfer parameters - use 10 LXON for testing
  const amount = ethers.parseUnits("10", 6); // 10 LXON (6 decimals)
  const recipient = signer.address; // Send to same address on Sepolia

  console.log("\nTransfer parameters:");
  console.log("  Amount:", ethers.formatUnits(amount, 6), "LXON");
  console.log("  Destination Chain ID:", sepoliaChainId, "(Sepolia)");
  console.log("  Recipient:", recipient);

  // Approve bridge to spend LXON
  console.log("\nApproving bridge to spend LXON...");
  const approveTx = await lxonToken.approve(lxonBridgeAddress, amount);
  console.log("  Transaction hash:", approveTx.hash);
  await approveTx.wait();
  console.log("  ✅ Approval confirmed");

  // Initiate transfer
  console.log("\nInitiating cross-chain transfer...");
  try {
    const transferTx = await lxonBridge.initiateTransfer(
      sepoliaChainId,
      lxonTokenAddress,
      amount,
      recipient
    );

    console.log("  Transaction hash:", transferTx.hash);
    console.log("  Waiting for confirmation...");

    const receipt = await transferTx.wait();
    console.log("  ✅ Transfer initiated successfully");
    console.log("  Block:", receipt.blockNumber);

    // Get transfer ID from event
    const transferEvent = receipt.logs.find((log: any) => {
      try {
        const parsed = lxonBridge.interface.parseLog(log);
        return parsed && parsed.name === "TransferInitiated";
      } catch {
        return false;
      }
    });

    if (transferEvent) {
      const parsed = lxonBridge.interface.parseLog(transferEvent);
      console.log("\nTransfer ID:", parsed.args.transferId);
      console.log("  Source Chain ID:", parsed.args.srcChainId.toString());
      console.log("  Destination Chain ID:", parsed.args.dstChainId.toString());
      console.log("  Token:", parsed.args.token);
      console.log("  Amount:", ethers.formatUnits(parsed.args.amount, 6), "LXON");
      console.log("  Recipient:", parsed.args.recipient);
    }

    console.log("\n⚠️  IMPORTANT:");
    console.log("  The transfer has been initiated on LXON network.");
    console.log("  To complete the transfer, you need:");
    console.log("  1. Attestation from 2 of 3 authorized attesters");
    console.log("  2. Complete the transfer on Sepolia network");
    console.log("\n  This is a TEST on Sepolia - no real value at risk.");

  } catch (error: any) {
    console.log("  ❌ Transfer failed:", error.message);
    console.log("\n  Possible reasons:");
    console.log("  - Peer bridge not configured correctly");
    console.log("  - Token not configured for transfer");
    console.log("  - Amount exceeds daily limit");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
