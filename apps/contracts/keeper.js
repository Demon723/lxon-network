// scripts/keeper.js — run every 5 minutes on server
const { ethers } = require("hardhat");
async function main() {
  const AUTO = process.env.AUTOMATOR_ADDR || "0xDa55F55201Ccd32F107D33e6b25c698083CBF37e";
  const auto = await ethers.getContractAt("PegAutomatorV2", AUTO);
  const [needed, data] = await auto.checkUpkeep("0x");
  if (!needed) { console.log("Peg healthy, nothing to do"); return; }
  const tx = await auto.performUpkeep(data);
  await tx.wait();
  console.log("Defended peg:", tx.hash);
}
main().catch(console.error);
