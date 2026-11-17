import { ethers } from "hardhat";
import { writeFileSync } from "fs";

async function main() {
  console.log("=== Deploying Missing Contracts to LXON Mainnet ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const network = await ethers.provider.getNetwork();
  console.log("Network:", network.name);
  console.log("Chain ID:", network.chainId.toString());

  if (network.chainId !== 724n) {
    console.error("❌ ERROR: Not on LXON mainnet (expected chain ID: 724)");
    process.exit(1);
  }

  const deployerBalance = await ethers.provider.getBalance(deployer.address);
  console.log("Deployer balance:", ethers.formatEther(deployerBalance), "LXON\n");

  const deployedContracts: any = {};

  // 1. Deploy WETH (Alternate)
  console.log("=== 1. Deploying WETH (Alternate) ===");
  const WETH = await ethers.getContractFactory("WETH");
  const weth = await WETH.deploy();
  await weth.waitForDeployment();
  const wethAddress = await weth.getAddress();
  deployedContracts.weth = wethAddress;
  console.log("✅ WETH deployed to:", wethAddress);

  // 2. Deploy LXON Token (Alternate) - using LXON.sol
  console.log("\n=== 2. Deploying LXON Token (Alternate) ===");
  const LXON = await ethers.getContractFactory("LXON");
  const lxon = await LXON.deploy(deployer.address);
  await lxon.waitForDeployment();
  const lxonAddress = await lxon.getAddress();
  deployedContracts.lxon = lxonAddress;
  console.log("✅ LXON deployed to:", lxonAddress);

  // 3. Deploy DEX Factory
  console.log("\n=== 3. Deploying DEX Factory ===");
  const DEXFactory = await ethers.getContractFactory("DEXFactory");
  const factory = await DEXFactory.deploy(deployer.address);
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  deployedContracts.dexFactory = factoryAddress;
  console.log("✅ DEX Factory deployed to:", factoryAddress);

  // 4. Deploy Universal Router
  console.log("\n=== 4. Deploying Universal Router ===");
  const UniversalRouter = await ethers.getContractFactory("UniversalRouter");
  const router = await UniversalRouter.deploy(factoryAddress, wethAddress);
  await router.waitForDeployment();
  const routerAddress = await router.getAddress();
  deployedContracts.universalRouter = routerAddress;
  console.log("✅ Universal Router deployed to:", routerAddress);

  // 5. Deploy Bridge Validator Registry - initialize pattern
  console.log("\n=== 5. Deploying Bridge Validator Registry ===");
  const BridgeValidatorRegistry = await ethers.getContractFactory("BridgeValidatorRegistry");
  const validatorRegistry = await BridgeValidatorRegistry.deploy();
  await validatorRegistry.waitForDeployment();
  const validatorRegistryAddress = await validatorRegistry.getAddress();
  // Initialize with deployer as admin, 1 validator (deployer), threshold 1, timelock = deployer
  await validatorRegistry.initialize(deployer.address, [deployer.address], 1, deployer.address);
  deployedContracts.bridgeValidatorRegistry = validatorRegistryAddress;
  console.log("✅ Bridge Validator Registry deployed to:", validatorRegistryAddress);

  // 6. Deploy LXON Bridge - initialize pattern
  console.log("\n=== 6. Deploying LXON Bridge ===");
  const LXONBridge = await ethers.getContractFactory("LxonBridge");
  const bridge = await LXONBridge.deploy();
  await bridge.waitForDeployment();
  const bridgeAddress = await bridge.getAddress();
  // Initialize bridge
  const chainId = network.chainId;
  await bridge.initialize(
    chainId,
    validatorRegistryAddress,
    deployer.address,
    wethAddress,
    deployer.address
  );
  deployedContracts.lxonBridge = bridgeAddress;
  console.log("✅ LXON Bridge deployed to:", bridgeAddress);

  // 7. Deploy Multi-Sig Validator Registry
  console.log("\n=== 7. Deploying Multi-Sig Validator Registry ===");
  const MultiSigValidatorRegistry = await ethers.getContractFactory("MultiSigValidatorRegistry");
  const multiSigRegistry = await MultiSigValidatorRegistry.deploy([deployer.address], 1);
  await multiSigRegistry.waitForDeployment();
  const multiSigRegistryAddress = await multiSigRegistry.getAddress();
  deployedContracts.multiSigValidatorRegistry = multiSigRegistryAddress;
  console.log("✅ Multi-Sig Validator Registry deployed to:", multiSigRegistryAddress);

  // Save deployment report
  const report = {
    network: {
      name: network.name,
      chainId: network.chainId.toString(),
      rpc: "https://rpc.lxon.in"
    },
    deployer: deployer.address,
    contracts: deployedContracts,
    deployedAt: new Date().toISOString()
  };

  writeFileSync(
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
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
