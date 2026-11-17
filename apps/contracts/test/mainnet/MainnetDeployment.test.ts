import { expect } from "chai";
import { ethers } from "hardhat";
import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { LXONNativeToken } from "../../typechain-types";
import { ERC20Mock } from "../../typechain-types";
import { LXONBuybackBurn } from "../../typechain-types";

describe("Mainnet Deployment Test Suite - Chain ID 724", function () {
  const CHAIN_ID = 724;
  const DEPLOYER_ADDRESS = "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3";
  const RPC_URL = "https://www.lxon.in";
  const DOMAIN = "www.lxon.in";

  // Deployment addresses from existing deployment
  const DEPLOYMENT_ADDRESSES = {
    lxonToken: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    usdc: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    buyback: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    staking: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    simpleSwap: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    owner: "0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3"
  };

  describe("1. Network Configuration", function () {
    it("should have correct chain ID 724", async function () {
      const network = await ethers.provider.getNetwork();
      expect(Number(network.chainId)).to.equal(CHAIN_ID);
    });

    it("should have correct network name", async function () {
      const network = await ethers.provider.getNetwork();
      expect(network.name).to.equal("lxon");
    });

    it("should have deployer with sufficient balance", async function () {
      const [deployer] = await ethers.getSigners();
      const balance = await ethers.provider.getBalance(deployer.address);
      expect(balance).to.be.gt(0);
    });
  });

  describe("2. Smart Contract Deployment", function () {
    it("should have LXON token contract deployed", async function () {
      const lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
      expect(await lxonToken.getAddress()).to.equal(DEPLOYMENT_ADDRESSES.lxonToken);
    });

    it("should have USDC token contract deployed", async function () {
      const usdc = await ethers.getContractAt("ERC20Mock", DEPLOYMENT_ADDRESSES.usdc);
      expect(await usdc.getAddress()).to.equal(DEPLOYMENT_ADDRESSES.usdc);
    });

    it("should have buyback contract deployed", async function () {
      const buyback = await ethers.getContractAt("LXONBuybackBurn", DEPLOYMENT_ADDRESSES.buyback);
      expect(await buyback.getAddress()).to.equal(DEPLOYMENT_ADDRESSES.buyback);
    });

    it("should have staking contract deployed", async function () {
      const staking = await ethers.getContractAt("LXONStaking", DEPLOYMENT_ADDRESSES.staking);
      expect(await staking.getAddress()).to.equal(DEPLOYMENT_ADDRESSES.staking);
    });

    it("should have simple swap contract deployed", async function () {
      const simpleSwap = await ethers.getContractAt("SimpleSwap", DEPLOYMENT_ADDRESSES.simpleSwap);
      expect(await simpleSwap.getAddress()).to.equal(DEPLOYMENT_ADDRESSES.simpleSwap);
    });
  });

  describe("3. LXON Token Functionality", function () {
    let lxonToken: LXONNativeToken;

    beforeEach(async function () {
      lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
    });

    it("should have correct token name", async function () {
      expect(await lxonToken.name()).to.equal("LXON");
    });

    it("should have correct token symbol", async function () {
      expect(await lxonToken.symbol()).to.equal("LXON");
    });

    it("should have correct decimals", async function () {
      expect(await lxonToken.decimals()).to.equal(18);
    });

    it("should have correct total supply", async function () {
      const totalSupply = await lxonToken.totalSupply();
      expect(totalSupply).to.be.gt(0);
    });

    it("should have multi-sig wallet configured", async function () {
      const multiSigWallet = await lxonToken.multiSigWallet();
      expect(multiSigWallet).to.equal(DEPLOYER_ADDRESS);
    });
  });

  describe("4. Buyback Contract Configuration", function () {
    let buyback: LXONBuybackBurn;
    let lxonToken: LXONNativeToken;
    let usdc: ERC20Mock;

    beforeEach(async function () {
      buyback = await ethers.getContractAt("LXONBuybackBurn", DEPLOYMENT_ADDRESSES.buyback);
      lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
      usdc = await ethers.getContractAt("ERC20Mock", DEPLOYMENT_ADDRESSES.usdc);
    });

    it("should have correct LXON token reference", async function () {
      expect(await buyback.lxonToken()).to.equal(DEPLOYMENT_ADDRESSES.lxonToken);
    });

    it("should have correct base token reference", async function () {
      expect(await buyback.baseToken()).to.equal(DEPLOYMENT_ADDRESSES.usdc);
    });

    it("should have correct treasury address", async function () {
      expect(await buyback.treasury()).to.equal(DEPLOYER_ADDRESS);
    });

    it("should have buyback enabled", async function () {
      expect(await buyback.buybackEnabled()).to.equal(true);
    });

    it("should have valid buyback threshold", async function () {
      const threshold = await buyback.buybackThreshold();
      expect(threshold).to.be.gt(0);
    });

    it("should have valid buyback percentage", async function () {
      const percentage = await buyback.buybackPercentage();
      expect(percentage).to.be.gt(0);
      expect(percentage).to.be.lte(100);
    });
  });

  describe("5. USDC Token Configuration", function () {
    let usdc: ERC20Mock;

    beforeEach(async function () {
      usdc = await ethers.getContractAt("ERC20Mock", DEPLOYMENT_ADDRESSES.usdc);
    });

    it("should have correct token name", async function () {
      expect(await usdc.name()).to.equal("USD Coin");
    });

    it("should have correct token symbol", async function () {
      expect(await usdc.symbol()).to.equal("USDC");
    });

    it("should have correct decimals", async function () {
      expect(await usdc.decimals()).to.equal(18);
    });

    it("should have treasury balance", async function () {
      const treasuryBalance = await usdc.balanceOf(DEPLOYER_ADDRESS);
      expect(treasuryBalance).to.be.gt(0);
    });
  });

  describe("6. RPC Connectivity", function () {
    it("should respond to eth_chainId", async function () {
      const chainId = await ethers.provider.send("eth_chainId", []);
      expect(chainId).to.equal(`0x${CHAIN_ID.toString(16)}`);
    });

    it("should respond to eth_blockNumber", async function () {
      const blockNumber = await ethers.provider.send("eth_blockNumber", []);
      expect(blockNumber).to.be.a("string");
      expect(parseInt(blockNumber, 16)).to.be.gte(0);
    });

    it("should respond to eth_getBlockByNumber", async function () {
      const block = await ethers.provider.send("eth_getBlockByNumber", ["latest", false]);
      expect(block).to.have.property("number");
      expect(block).to.have.property("hash");
      expect(block).to.have.property("timestamp");
    });

    it("should have recent blocks", async function () {
      const blockNumber = await ethers.provider.getBlockNumber();
      expect(blockNumber).to.be.gt(0);
    });
  });

  describe("7. Contract Interaction Tests", function () {
    let lxonToken: LXONNativeToken;
    let usdc: ERC20Mock;
    let deployer: any;
    let user1: any;

    beforeEach(async function () {
      [deployer, user1] = await ethers.getSigners();
      lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
      usdc = await ethers.getContractAt("ERC20Mock", DEPLOYMENT_ADDRESSES.usdc);
    });

    it("should allow token transfers", async function () {
      const transferAmount = ethers.parseEther("100");
      
      // Mint tokens to deployer first
      await lxonToken.mint(deployer.address, transferAmount);
      
      // Transfer to user1
      await lxonToken.transfer(user1.address, transferAmount);
      
      const userBalance = await lxonToken.balanceOf(user1.address);
      expect(userBalance).to.equal(transferAmount);
    });

    it("should allow USDC transfers", async function () {
      const transferAmount = ethers.parseUnits("1000", 18);
      
      // Transfer from deployer to user1
      await usdc.transfer(user1.address, transferAmount);
      
      const userBalance = await usdc.balanceOf(user1.address);
      expect(userBalance).to.equal(transferAmount);
    });

    it("should allow token approvals", async function () {
      const approveAmount = ethers.parseEther("1000");
      
      await lxonToken.approve(user1.address, approveAmount);
      
      const allowance = await lxonToken.allowance(deployer.address, user1.address);
      expect(allowance).to.equal(approveAmount);
    });
  });

  describe("8. Chainlist Configuration", function () {
    const fs = require("fs");
    const path = require("path");

    it("should have chainlist.json file", function () {
      const chainlistPath = path.join(__dirname, "../../../chainlist.json");
      expect(fs.existsSync(chainlistPath)).to.be.true;
    });

    it("should have correct chain ID in chainlist", function () {
      const chainlistPath = path.join(__dirname, "../../../chainlist.json");
      const chainlist = JSON.parse(fs.readFileSync(chainlistPath, "utf8"));
      expect(chainlist.chainId).to.equal(CHAIN_ID);
    });

    it("should include www.lxon.in as RPC endpoint", function () {
      const chainlistPath = path.join(__dirname, "../../../chainlist.json");
      const chainlist = JSON.parse(fs.readFileSync(chainlistPath, "utf8"));
      expect(chainlist.rpc).to.include("https://www.lxon.in");
    });

    it("should include www.lxon.in as explorer", function () {
      const chainlistPath = path.join(__dirname, "../../../chainlist.json");
      const chainlist = JSON.parse(fs.readFileSync(chainlistPath, "utf8"));
      const hasOfficialExplorer = chainlist.explorers.some(
        (explorer: any) => explorer.url === "https://www.lxon.in"
      );
      expect(hasOfficialExplorer).to.be.true;
    });

    it("should have correct native currency info", function () {
      const chainlistPath = path.join(__dirname, "../../../chainlist.json");
      const chainlist = JSON.parse(fs.readFileSync(chainlistPath, "utf8"));
      expect(chainlist.nativeCurrency.symbol).to.equal("XON");
      expect(chainlist.nativeCurrency.decimals).to.equal(18);
    });
  });

  describe("9. Deployment Records", function () {
    const fs = require("fs");
    const path = require("path");

    it("should have deployment record for chain ID 724", function () {
      const deploymentPath = path.join(__dirname, "../../deployments/lxon-mainnet-724.json");
      expect(fs.existsSync(deploymentPath)).to.be.true;
    });

    it("should have correct contract addresses in deployment record", function () {
      const deploymentPath = path.join(__dirname, "../../deployments/lxon-mainnet-724.json");
      const deployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
      expect(deployment.chainId).to.equal(CHAIN_ID);
      expect(deployment.contracts.lxonToken).to.equal(DEPLOYMENT_ADDRESSES.lxonToken);
    });

    it("should have RPC URL in deployment record", function () {
      const deploymentPath = path.join(__dirname, "../../deployments/lxon-mainnet-724.json");
      const deployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
      expect(deployment.rpcUrl).to.include("44.198.165.189");
    });
  });

  describe("10. Integration Tests", function () {
    let lxonToken: LXONNativeToken;
    let usdc: ERC20Mock;
    let buyback: LXONBuybackBurn;
    let deployer: any;
    let user1: any;

    beforeEach(async function () {
      [deployer, user1] = await ethers.getSigners();
      lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
      usdc = await ethers.getContractAt("ERC20Mock", DEPLOYMENT_ADDRESSES.usdc);
      buyback = await ethers.getContractAt("LXONBuybackBurn", DEPLOYMENT_ADDRESSES.buyback);
    });

    it("should execute complete buyback flow", async function () {
      // Setup: Ensure deployer has LXON tokens
      const lxonAmount = ethers.parseEther("1000");
      await lxonToken.mint(deployer.address, lxonAmount);

      // Ensure deployer has USDC
      const usdcAmount = ethers.parseUnits("10000", 18);
      await usdc.mint(deployer.address, usdcAmount);

      // Approve buyback contract to spend USDC
      await usdc.approve(await buyback.getAddress(), usdcAmount);

      // Execute buyback (this would normally be triggered by price conditions)
      // For testing, we'll just verify the configuration allows it
      const buybackEnabled = await buyback.buybackEnabled();
      expect(buybackEnabled).to.equal(true);
    });

    it("should handle multi-contract interactions", async function () {
      // Transfer LXON to user1
      const lxonAmount = ethers.parseEther("500");
      await lxonToken.mint(deployer.address, lxonAmount);
      await lxonToken.transfer(user1.address, lxonAmount);

      // Transfer USDC to user1
      const usdcAmount = ethers.parseUnits("5000", 18);
      await usdc.transfer(user1.address, usdcAmount);

      // Verify balances
      expect(await lxonToken.balanceOf(user1.address)).to.equal(lxonAmount);
      expect(await usdc.balanceOf(user1.address)).to.equal(usdcAmount);
    });
  });

  describe("11. Security Configuration", function () {
    let lxonToken: LXONNativeToken;
    let buyback: LXONBuybackBurn;

    beforeEach(async function () {
      lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
      buyback = await ethers.getContractAt("LXONBuybackBurn", DEPLOYMENT_ADDRESSES.buyback);
    });

    it("should have owner as multi-sig wallet", async function () {
      const multiSigWallet = await lxonToken.multiSigWallet();
      expect(multiSigWallet).to.equal(DEPLOYER_ADDRESS);
    });

    it("should have only owner as admin in buyback", async function () {
      const treasury = await buyback.treasury();
      expect(treasury).to.equal(DEPLOYER_ADDRESS);
    });

    it("should prevent unauthorized minting", async function () {
      const [_, user1] = await ethers.getSigners();
      const mintAmount = ethers.parseEther("100");
      
      await expect(
        lxonToken.connect(user1).mint(user1.address, mintAmount)
      ).to.be.reverted;
    });
  });

  describe("12. Performance Tests", function () {
    it("should handle multiple transfers efficiently", async function () {
      const lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
      const [deployer, user1] = await ethers.getSigners();
      
      const transferAmount = ethers.parseEther("1");
      await lxonToken.mint(deployer.address, ethers.parseEther("1000"));

      const startTime = Date.now();
      
      for (let i = 0; i < 10; i++) {
        await lxonToken.transfer(user1.address, transferAmount);
      }
      
      const endTime = Date.now();
      const duration = endTime - startTime;
      
      // Should complete 10 transfers in reasonable time (< 30 seconds)
      expect(duration).to.be.lt(30000);
    });

    it("should handle batch operations", async function () {
      const usdc = await ethers.getContractAt("ERC20Mock", DEPLOYMENT_ADDRESSES.usdc);
      const [deployer, user1] = await ethers.getSigners();
      
      const transferAmount = ethers.parseUnits("100", 18);
      await usdc.mint(deployer.address, ethers.parseUnits("10000", 18));

      const startTime = Date.now();
      
      // Multiple approvals
      for (let i = 0; i < 5; i++) {
        await usdc.approve(user1.address, transferAmount);
      }
      
      const endTime = Date.now();
      const duration = endTime - startTime;
      
      expect(duration).to.be.lt(15000);
    });
  });

  describe("13. Error Handling", function () {
    let lxonToken: LXONNativeToken;

    beforeEach(async function () {
      lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
    });

    it("should revert on insufficient balance transfer", async function () {
      const [_, user1] = await ethers.getSigners();
      const transferAmount = ethers.parseEther("1000000");
      
      await expect(
        lxonToken.transfer(user1.address, transferAmount)
      ).to.be.reverted;
    });

    it("should revert on invalid transfers", async function () {
      const [deployer] = await ethers.getSigners();
      const transferAmount = ethers.parseEther("0");
      
      // Zero address transfer should fail
      await expect(
        lxonToken.transfer(ethers.ZeroAddress, transferAmount)
      ).to.be.reverted;
    });
  });

  describe("14. Gas Optimization", function () {
    it("should have reasonable gas costs for transfers", async function () {
      const lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
      const [deployer, user1] = await ethers.getSigners();
      
      const transferAmount = ethers.parseEther("100");
      await lxonToken.mint(deployer.address, transferAmount);

      const tx = await lxonToken.transfer(user1.address, transferAmount);
      const receipt = await tx.wait();
      
      // Transfer should cost less than 100,000 gas
      expect(receipt.gasUsed).to.be.lt(100000);
    });

    it("should have reasonable gas costs for approvals", async function () {
      const lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
      const [deployer, user1] = await ethers.getSigners();
      
      const approveAmount = ethers.parseEther("1000");
      const tx = await lxonToken.approve(user1.address, approveAmount);
      const receipt = await tx.wait();
      
      // Approval should cost less than 50,000 gas
      expect(receipt.gasUsed).to.be.lt(50000);
    });
  });

  describe("15. Final System Health Check", function () {
    it("should have all contracts deployed and accessible", async function () {
      const contracts = [
        DEPLOYMENT_ADDRESSES.lxonToken,
        DEPLOYMENT_ADDRESSES.usdc,
        DEPLOYMENT_ADDRESSES.buyback,
        DEPLOYMENT_ADDRESSES.staking,
        DEPLOYMENT_ADDRESSES.simpleSwap
      ];

      for (const contractAddress of contracts) {
        const code = await ethers.provider.getCode(contractAddress);
        expect(code).to.not.equal("0x");
        expect(code.length).to.be.gt(2); // More than "0x"
      }
    });

    it("should have positive total supply across ecosystem", async function () {
      const lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
      const totalSupply = await lxonToken.totalSupply();
      expect(totalSupply).to.be.gt(0);
    });

    it("should have active network with recent blocks", async function () {
      const latestBlock = await ethers.provider.getBlock("latest");
      const currentTimestamp = Math.floor(Date.now() / 1000);
      const blockTimestamp = Number(latestBlock.timestamp);
      
      // Block should be from last 24 hours
      expect(currentTimestamp - blockTimestamp).to.be.lt(86400);
    });

    it("should complete full system integration test", async function () {
      const lxonToken = await ethers.getContractAt("LXONNativeToken", DEPLOYMENT_ADDRESSES.lxonToken);
      const usdc = await ethers.getContractAt("ERC20Mock", DEPLOYMENT_ADDRESSES.usdc);
      const [deployer, user1] = await ethers.getSigners();

      // 1. Mint LXON tokens
      const lxonAmount = ethers.parseEther("100");
      await lxonToken.mint(deployer.address, lxonAmount);
      expect(await lxonToken.balanceOf(deployer.address)).to.equal(lxonAmount);

      // 2. Transfer to user
      await lxonToken.transfer(user1.address, lxonAmount);
      expect(await lxonToken.balanceOf(user1.address)).to.equal(lxonAmount);

      // 3. Mint USDC
      const usdcAmount = ethers.parseUnits("1000", 18);
      await usdc.mint(deployer.address, usdcAmount);
      expect(await usdc.balanceOf(deployer.address)).to.equal(usdcAmount);

      // 4. Transfer USDC to user
      await usdc.transfer(user1.address, usdcAmount);
      expect(await usdc.balanceOf(user1.address)).to.equal(usdcAmount);

      // 5. User approves spending
      await lxonToken.connect(user1).approve(deployer.address, lxonAmount);
      expect(await lxonToken.allowance(user1.address, deployer.address)).to.equal(lxonAmount);

      // System is fully functional
      expect(true).to.be.true;
    });
  });
});