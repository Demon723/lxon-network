const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

async function getContractBytecode(contractName, artifactName = contractName) {
  const artifactPath = path.join(__dirname, `../artifacts/contracts/${contractName}.sol/${artifactName}.json`);
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  return artifact.bytecode;
}

async function getContractABI(contractName, artifactName = contractName) {
  const artifactPath = path.join(__dirname, `../artifacts/contracts/${contractName}.sol/${artifactName}.json`);
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  return artifact.abi;
}

async function main() {
  console.log("=== Deploying Missing Contracts to LXON Mainnet ===\n");

  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  const rpcUrl = process.env.LXON_RPC_URL || "https://rpc.lxon.in";

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log("Deploying with account:", wallet.address);

  const network = await provider.getNetwork();
  console.log("Network:", network.name);
  console.log("Chain ID:", network.chainId.toString());

  if (network.chainId !== 724n) {
    console.error("❌ ERROR: Not on LXON mainnet (expected chain ID: 724)");
    process.exit(1);
  }

  const balance = await provider.getBalance(wallet.address);
  console.log("Deployer balance:", ethers.formatEther(balance), "LXON\n");

  const deployedContracts = {};

  try {
    // Use already deployed addresses from previous attempt
    const wethAddress = "0x4d857b3e030bA985c5D32611Ff69238975790Be7";
    const lxonAddress = "0x6f872Ac9bBDF58434b9976ea0f7e2F3f5b44dC35";
    const factoryAddress = "0xd99d3d037B124AA1Ea153B3D601a29BC75872a06";
    const routerAddress = "0xC416AC6B446Adf791Ef83e6B0f7FF2dc708F247a";

    deployedContracts.weth = wethAddress;
    deployedContracts.lxon = lxonAddress;
    deployedContracts.dexFactory = factoryAddress;
    deployedContracts.universalRouter = routerAddress;

    console.log("=== Using Already Deployed Contracts ===");
    console.log("WETH9:", wethAddress);
    console.log("LXON:", lxonAddress);
    console.log("DEX Factory:", factoryAddress);
    console.log("Universal Router:", routerAddress);

    // 5. Deploy Bridge Validator Registry
    console.log("\n=== 5. Deploying Bridge Validator Registry ===");
    const validatorBytecode = await getContractBytecode("BridgeValidatorRegistry");
    const validatorABI = await getContractABI("BridgeValidatorRegistry");
    const validatorFactory = new ethers.ContractFactory(validatorABI, validatorBytecode, wallet);
    const validatorRegistry = await validatorFactory.deploy();
    await validatorRegistry.waitForDeployment();
    const validatorRegistryAddress = await validatorRegistry.getAddress();
    console.log("✅ Bridge Validator Registry deployed to:", validatorRegistryAddress);
    // Initialize
    console.log("  Initializing...");
    const initTx = await validatorRegistry.initialize(wallet.address, [wallet.address], 1, wallet.address);
    await initTx.wait();
    console.log("  ✅ Initialized");
    deployedContracts.bridgeValidatorRegistry = validatorRegistryAddress;

    // 6. Deploy LXON Bridge
    console.log("\n=== 6. Deploying LXON Bridge ===");
    const bridgeBytecode = await getContractBytecode("LxonBridge", "LxonBridge");
    const bridgeABI = await getContractABI("LxonBridge", "LxonBridge");
    const bridgeFactory = new ethers.ContractFactory(bridgeABI, bridgeBytecode, wallet);
    const bridge = await bridgeFactory.deploy();
    await bridge.waitForDeployment();
    const bridgeAddress = await bridge.getAddress();
    console.log("✅ LXON Bridge deployed to:", bridgeAddress);
    // Initialize
    console.log("  Initializing...");
    const chainId = network.chainId;
    const bridgeInitTx = await bridge.initialize(chainId, validatorRegistryAddress, wallet.address, wethAddress, wallet.address);
    await bridgeInitTx.wait();
    console.log("  ✅ Initialized");
    deployedContracts.lxonBridge = bridgeAddress;

    // 7. Deploy Multi-Sig Validator Registry
    console.log("\n=== 7. Deploying Multi-Sig Validator Registry ===");
    const multiSigBytecode = await getContractBytecode("MultiSigValidatorRegistry");
    const multiSigABI = await getContractABI("MultiSigValidatorRegistry");
    const multiSigFactory = new ethers.ContractFactory(multiSigABI, multiSigBytecode, wallet);
    const multiSigRegistry = await multiSigFactory.deploy([wallet.address], 1);
    await multiSigRegistry.waitForDeployment();
    const multiSigRegistryAddress = await multiSigRegistry.getAddress();
    deployedContracts.multiSigValidatorRegistry = multiSigRegistryAddress;
    console.log("✅ Multi-Sig Validator Registry deployed to:", multiSigRegistryAddress);

    // Save deployment report
    const report = {
      network: {
        name: network.name,
        chainId: network.chainId.toString(),
        rpc: rpcUrl
      },
      deployer: wallet.address,
      contracts: deployedContracts,
      deployedAt: new Date().toISOString()
    };

    fs.writeFileSync(
      "/Users/adikamble/LXON/LXON/apps/contracts/deployments/new-deployments-724.json",
      JSON.stringify(report, null, 2)
    );

    console.log("\n=== Deployment Complete ===");
    console.log("All 7 contracts deployed successfully!");
    console.log("\nReport saved to: deployments/new-deployments-724.json");
    console.log("\n=== Deployed Addresses ===");
    for (const [name, address] of Object.entries(deployedContracts)) {
      console.log(`${name}: ${address}`);
    }

  } catch (error) {
    console.error("\n❌ Deployment failed:");
    console.error(error.message);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
