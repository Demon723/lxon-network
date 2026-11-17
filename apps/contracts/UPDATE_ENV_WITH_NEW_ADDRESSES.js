const fs = require("fs");

const envPath = "/Users/adikamble/LXON/LXON/apps/contracts/.env";
const envBackupPath = "/Users/adikamble/LXON/LXON/apps/contracts/.env.backup";

// Read current .env
let envContent = fs.readFileSync(envPath, "utf8");

// Backup original
fs.writeFileSync(envBackupPath, envContent);

// Add new addresses
const newAddresses = `
# NEWLY DEPLOYED CONTRACTS (Oct 6, 2026)
WETH_NEW=0x4d857b3e030bA985c5D32611Ff69238975790Be7
LXON_NEW=0x6f872Ac9bBDF58434b9976ea0f7e2F3f5b44dC35
DEX_FACTORY=0xd99d3d037B124AA1Ea153B3D601a29BC75872a06
UNIVERSAL_ROUTER=0xC416AC6B446Adf791Ef83e6B0f7FF2dc708F247a
BRIDGE_VALIDATOR_REGISTRY=0x4FDa2fC19249F6193b19338639fc161345EB97ff
LXON_BRIDGE=0xfDC175150714C7663D626Dd551f829b1Ba748877
MULTISIG_VALIDATOR_REGISTRY=0x69e08b01b769Ec63944473Fa5AdAc4784fAd6Fb3
DEX_PAIR_NEW=0x6a4c5e73e6A075f96391fDC0a164D52804cA0519
`;

// Append to .env
envContent += newAddresses;

fs.writeFileSync(envPath, envContent);

console.log("✅ .env updated with new contract addresses");
console.log("✅ Backup saved to .env.backup");
console.log("\nAdded addresses:");
console.log("- WETH_NEW");
console.log("- LXON_NEW");
console.log("- DEX_FACTORY");
console.log("- UNIVERSAL_ROUTER");
console.log("- BRIDGE_VALIDATOR_REGISTRY");
console.log("- LXON_BRIDGE");
console.log("- MULTISIG_VALIDATOR_REGISTRY");
console.log("- DEX_PAIR_NEW");
