import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log("🔄 Initiating Cross-Chain Transfer: 100 LXON from LXON to Polygon");
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
  const polygonChainId = 137;
  const polygonLxonAddress = "0x8E7BE3BC21F8eDa71d192ECa502705c10274a813";

  // Connect to contracts
  const lxonBridge = await ethers.getContractAt("LxonBridgeMultiSig", lxonBridgeAddress);
  const lxonToken = await ethers.getContractAt("LXONNativeTokenEnhanced", lxonTokenAddress);

  console.log("\nContract addresses:");
  console.log("  LXON Bridge:", lxonBridgeAddress);
  console.log("  LXON Token:", lxonTokenAddress);
  console.log("  Polygon Chain ID:", polygonChainId);
  console.log("  Polygon LXON Token:", polygonLxonAddress);

  // Check LXON balance
  console.log("\nChecking LXON balance...");
  const balance = await lxonToken.balanceOf(signer.address);
  console.log("LXON balance:", ethers.formatUnits(balance, 6), "LXON");

  if (balance < ethers.parseUnits("100", 6)) {
    console.log("❌ Insufficient LXON balance. Need 100 LXON.");
    return;
  }

  // Transfer parameters - use 100 LXON
  const amount = ethers.parseUnits("100", 6);
  const recipient = signer.address;

  console.log("\nTransfer parameters:");
  console.log("  Amount:", ethers.formatUnits(amount, 6), "LXON");
  console.log("  Destination Chain ID:", polygonChainId, "(Polygon)");
  console.log("  Destination Token:", polygonLxonAddress);
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
      polygonChainId,
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
      console.log("\n✅ Transfer Details:");
      console.log("  Transfer ID:", parsed.args.transferId);
      console.log("  Source Chain ID:", parsed.args.srcChainId.toString());
      console.log("  Destination Chain ID:", parsed.args.dstChainId.toString());
      console.log("  Token:", parsed.args.token);
      console.log("  Amount:", ethers.formatUnits(parsed.args.amount, 6), "LXON");
      console.log("  Recipient:", parsed.args.recipient);
    }

    console.log("\n🎉 Cross-chain transfer of 100 LXON to Polygon initiated successfully!");
    console.log("\n⚠️  Next Steps:");
    console.log("  1. Get attestation from 2 of 3 MultiSigAttester signers");
    console.log("  2. Complete the transfer on Polygon bridge");
    console.log("  3. Verify token arrival on Polygon");

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
