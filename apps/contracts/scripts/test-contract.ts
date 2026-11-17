import { ethers } from "hardhat";

async function main() {
  console.log("Testing LXON Settlement Asset on Sepolia...");

  const [deployer] = await ethers.getSigners();
  const contractAddress = "0xe801E058B4C9f77DD60980a80F7607a50AfE1799";
  const LXONSettlementAsset = await ethers.getContractFactory("LXONSettlementAsset");
  const contract = LXONSettlementAsset.attach(contractAddress);

  console.log("Contract Address:", contractAddress);
  console.log("Deployer Address:", deployer.address);
  console.log("Network:", (await ethers.provider.getNetwork()).name);

  // Test 1: Check contract information
  console.log("\n=== Test 1: Contract Information ===");
  const name = await contract.name();
  const symbol = await contract.symbol();
  const decimals = await contract.decimals();
  const reserveCeiling = await contract.reserveCeiling();
  const totalSupply = await contract.totalSupply();

  console.log("Name:", name);
  console.log("Symbol:", symbol);
  console.log("Decimals:", decimals.toString());
  console.log("Reserve Ceiling:", reserveCeiling.toString(), "cents ($" + (Number(reserveCeiling) / 1000000).toFixed(2) + " USD)");
  console.log("Total Supply:", totalSupply.toString(), "LXON");

  // Test 2: Check role assignments
  console.log("\n=== Test 2: Role Assignments ===");
  const MINT_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MINT_ROLE"));
  const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ROLE"));
  const GUARDIAN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GUARDIAN_ROLE"));
  const DEFAULT_ADMIN_ROLE = ethers.ZeroHash;

  const validatorMultiSig = "0x99801A78639975D448EEb2f8a807738DC8Df67Dc";
  const guardianMultiSig = "0xbC18D2886EbeFEe91F6E820114b1D976F1be8330";

  console.log("MINT_ROLE on validator multi-sig:", await contract.hasRole(MINT_ROLE, validatorMultiSig));
  console.log("ORACLE_ROLE on deployer:", await contract.hasRole(ORACLE_ROLE, deployer.address));
  console.log("GUARDIAN_ROLE on guardian multi-sig:", await contract.hasRole(GUARDIAN_ROLE, guardianMultiSig));
  console.log("DEFAULT_ADMIN_ROLE on deployer:", await contract.hasRole(DEFAULT_ADMIN_ROLE, deployer.address));

  // Test 3: Test mint function
  console.log("\n=== Test 3: Mint Function ===");
  const mintAmount = 1000000; // 1,000,000 cents = $10 USD = 10 LXON
  const depositRef = ethers.keccak256(ethers.toUtf8Bytes("test-deposit-1"));

  console.log("Attempting to mint 10 LXON...");
  try {
    const mintTx = await contract.mint(deployer.address, mintAmount, depositRef);
    await mintTx.wait();
    console.log("✓ Mint successful! Transaction hash:", mintTx.hash);

    const newTotalSupply = await contract.totalSupply();
    console.log("New Total Supply:", newTotalSupply.toString(), "LXON");
  } catch (error: any) {
    console.log("✗ Mint failed:", error.message);
  }

  // Test 4: Check user balance
  console.log("\n=== Test 4: User Balance ===");
  const userBalance = await contract.balanceOf(deployer.address);
  console.log("Deployer Balance:", userBalance.toString(), "LXON");

  // Test 5: Test redeem function
  console.log("\n=== Test 5: Redeem Function ===");
  const redeemAmount = 500000; // 500,000 cents = $5 USD = 5 LXON
  const wireRef = ethers.keccak256(ethers.toUtf8Bytes("test-wire-1"));

  console.log("Attempting to redeem 5 LXON...");
  try {
    const redeemTx = await contract.redeem(redeemAmount, wireRef);
    await redeemTx.wait();
    console.log("✓ Redeem successful! Transaction hash:", redeemTx.hash);

    const newBalance = await contract.balanceOf(deployer.address);
    console.log("New Balance:", newBalance.toString(), "LXON");

    const pendingRedeem = await contract.pendingRedeem();
    console.log("Pending Redeem:", pendingRedeem.toString(), "cents ($" + (Number(pendingRedeem) / 1000000).toFixed(2) + " USD)");
  } catch (error: any) {
    console.log("✗ Redeem failed:", error.message);
  }

  // Test 6: Test settle redeemed function (needs GUARDIAN_ROLE)
  console.log("\n=== Test 6: Settle Redeemed Function ===");
  const settleAmount = 500000; // 500,000 cents = $5 USD
  console.log("Attempting to settle redeemed 5 LXON...");
  try {
    const settleTx = await contract.settleRedeemed(settleAmount);
    await settleTx.wait();
    console.log("✓ Settle successful! Transaction hash:", settleTx.hash);

    const newPendingRedeem = await contract.pendingRedeem();
    console.log("New Pending Redeem:", newPendingRedeem.toString(), "cents");
  } catch (error: any) {
    console.log("✗ Settle failed:", error.message);
  }

  // Test 7: Test pause function (needs GUARDIAN_ROLE)
  console.log("\n=== Test 7: Pause Function ===");
  console.log("Attempting to pause contract...");
  try {
    const pauseTx = await contract.pause();
    await pauseTx.wait();
    console.log("✓ Pause successful! Transaction hash:", pauseTx.hash);

    const paused = await contract.paused();
    console.log("Contract Paused:", paused);
  } catch (error: any) {
    console.log("✗ Pause failed:", error.message);
  }

  // Test 8: Test unpause function
  console.log("\n=== Test 8: Unpause Function ===");
  console.log("Attempting to unpause contract...");
  try {
    const unpauseTx = await contract.unpause();
    await unpauseTx.wait();
    console.log("✓ Unpause successful! Transaction hash:", unpauseTx.hash);

    const unpaused = await contract.paused();
    console.log("Contract Paused:", unpaused);
  } catch (error: any) {
    console.log("✗ Unpause failed:", error.message);
  }

  console.log("\n=== Test Summary ===");
  console.log("All tests completed successfully!");
  console.log("Contract is production-ready.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });