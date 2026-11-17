import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { LXONHardened, LXONStakingHardened } from "../typechain-types";

/**
 * Performance Benchmarks
 * 
 * These tests measure gas costs and execution times for critical operations
 * to ensure they meet performance targets and identify optimization opportunities.
 */

describe("LXON Performance Benchmarks", () => {
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let lxon: LXONHardened;
  let staking: LXONStakingHardened;

  const TIMELOCK_DELAY = 172800;
  const MINTER_ROLE = ethers.id("MINTER_ROLE");
  const BURNER_ROLE = ethers.id("BURNER_ROLE");

  // Performance targets (in gas units).
  // LXONHardened uses ERC20Votes checkpointing, AccessControl role checks and
  // a TimelockController deployment, so budgets are set with ~30% headroom
  // over measured baseline to catch regressions without false failures.
  const TARGETS = {
    mintEmission: 200000, // Target: <200k gas (measured ~122k)
    burn: 100000, // Target: <100k gas (measured ~70k)
    transfer: 80000, // Target: <80k gas (measured ~56k)
    stake: 350000, // Target: <350k gas (measured ~285k)
    unstake: 120000, // Target: <120k gas (measured ~86k)
    createVestingSchedule: 150000, // Target: <150k gas
  };

  beforeEach(async () => {
    [owner, user1, user2] = await ethers.getSigners();

    const LXONFactory = await ethers.getContractFactory("LXONHardened");
    lxon = await LXONFactory.deploy(owner.address, TIMELOCK_DELAY);
    await lxon.waitForDeployment();

    const StakingFactory = await ethers.getContractFactory("LXONStakingHardened");
    staking = await StakingFactory.deploy(
      await lxon.getAddress(),
      owner.address,
      TIMELOCK_DELAY
    );
    await staking.waitForDeployment();
  });

  describe("Gas Cost Benchmarks", () => {
    it("Should measure mintEmission gas cost", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      const amount = ethers.parseEther("1000000");

      const tx = await lxon.connect(owner).mintEmission(amount);
      const receipt = await tx.wait();
      if (!receipt) throw new Error("No receipt");

      const gasUsed = receipt.gasUsed;
      console.log(`mintEmission gas cost: ${gasUsed.toString()}`);

      expect(gasUsed).to.be.lessThan(TARGETS.mintEmission);
    });

    it("Should measure burn gas cost", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));
      await lxon.transfer(user1.address, ethers.parseEther("100000"));

      const burnAmount = ethers.parseEther("1000");
      const tx = await lxon.connect(user1).burn(burnAmount);
      const receipt = await tx.wait();
      if (!receipt) throw new Error("No receipt");

      const gasUsed = receipt.gasUsed;
      console.log(`burn gas cost: ${gasUsed.toString()}`);

      expect(gasUsed).to.be.lessThan(TARGETS.burn);
    });

    it("Should measure transfer gas cost", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));
      await lxon.transfer(user1.address, ethers.parseEther("100000"));

      const transferAmount = ethers.parseEther("1000");
      const tx = await lxon.connect(user1).transfer(user2.address, transferAmount);
      const receipt = await tx.wait();
      if (!receipt) throw new Error("No receipt");

      const gasUsed = receipt.gasUsed;
      console.log(`transfer gas cost: ${gasUsed.toString()}`);

      expect(gasUsed).to.be.lessThan(TARGETS.transfer);
    });

    it("Should measure stake gas cost", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("10000000"));
      await lxon.transfer(user1.address, ethers.parseEther("1000000"));
      await lxon
        .connect(user1)
        .approve(await staking.getAddress(), ethers.parseEther("1000000"));

      const SUBNET_ID = ethers.id("perf-test");
      await staking.grantRole(
        ethers.id("SUBNET_MANAGER_ROLE"),
        owner.address
      );
      await staking.connect(owner).createSubnet(SUBNET_ID, 5000);

      const stakeAmount = ethers.parseEther("10000");
      const tx = await staking
        .connect(user1)
        .stake(stakeAmount, SUBNET_ID, 30 * 24 * 60 * 60);
      const receipt = await tx.wait();
      if (!receipt) throw new Error("No receipt");

      const gasUsed = receipt.gasUsed;
      console.log(`stake gas cost: ${gasUsed.toString()}`);

      expect(gasUsed).to.be.lessThan(TARGETS.stake);
    });

    it("Should measure unstake gas cost", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("10000000"));
      await lxon.transfer(user1.address, ethers.parseEther("1000000"));
      await lxon
        .connect(user1)
        .approve(await staking.getAddress(), ethers.parseEther("1000000"));

      const SUBNET_ID = ethers.id("perf-test");
      await staking.grantRole(
        ethers.id("SUBNET_MANAGER_ROLE"),
        owner.address
      );
      await staking.connect(owner).createSubnet(SUBNET_ID, 5000);

      const stakeAmount = ethers.parseEther("10000");
      await staking
        .connect(user1)
        .stake(stakeAmount, SUBNET_ID, 30 * 24 * 60 * 60);

      // Fast forward time
      await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60 + 1]);
      await ethers.provider.send("evm_mine", []);

      const tx = await staking.connect(user1).unstake(0);
      const receipt = await tx.wait();
      if (!receipt) throw new Error("No receipt");

      const gasUsed = receipt.gasUsed;
      console.log(`unstake gas cost: ${gasUsed.toString()}`);

      expect(gasUsed).to.be.lessThan(TARGETS.unstake);
    });
  });

  describe("Execution Time Benchmarks", () => {
    it("Should measure batch operation execution time", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("10000000"));

      const startTime = Date.now();
      const numTransfers = 100;
      const transferAmount = ethers.parseEther("100");

      for (let i = 0; i < numTransfers; i++) {
        await lxon.transfer(user1.address, transferAmount);
      }

      const endTime = Date.now();
      const executionTime = endTime - startTime;
      const avgTimePerTransfer = executionTime / numTransfers;

      console.log(`Batch transfer execution time: ${executionTime}ms`);
      console.log(`Average time per transfer: ${avgTimePerTransfer}ms`);

      // Target: <1 second for 100 transfers
      expect(executionTime).to.be.lessThan(1000);
    });

    it("Should measure concurrent staking operations", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("10000000"));
      await lxon.transfer(user1.address, ethers.parseEther("1000000"));
      await lxon
        .connect(user1)
        .approve(await staking.getAddress(), ethers.parseEther("1000000"));

      const SUBNET_ID = ethers.id("concurrent-test");
      await staking.grantRole(
        ethers.id("SUBNET_MANAGER_ROLE"),
        owner.address
      );
      await staking.connect(owner).createSubnet(SUBNET_ID, 5000);

      const startTime = Date.now();
      const numStakes = 50;
      const stakeAmount = ethers.parseEther("1000");

      for (let i = 0; i < numStakes; i++) {
        await staking
          .connect(user1)
          .stake(stakeAmount, SUBNET_ID, 30 * 24 * 60 * 60);
      }

      const endTime = Date.now();
      const executionTime = endTime - startTime;
      const avgTimePerStake = executionTime / numStakes;

      console.log(`Concurrent staking execution time: ${executionTime}ms`);
      console.log(`Average time per stake: ${avgTimePerStake}ms`);

      // Target: <2 seconds for 50 stakes
      expect(executionTime).to.be.lessThan(2000);
    });
  });

  describe("Memory Usage Benchmarks", () => {
    it("Should measure contract deployment size", async () => {
      const LXONFactory = await ethers.getContractFactory("LXONHardened");
      const deploymentTx = await LXONFactory.getDeployTransaction(
        owner.address,
        TIMELOCK_DELAY
      );

      const deploymentData = deploymentTx.data;
      const deploymentSize = deploymentData ? deploymentData.length : 0;

      console.log(`LXON contract deployment size: ${deploymentSize} bytes`);

      // Target: <50KB deployment size
      expect(deploymentSize).to.be.lessThan(50000);
    });

    it("Should measure storage usage patterns", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));

      // Mint multiple times to test storage growth
      const numMints = 100;
      for (let i = 0; i < numMints; i++) {
        await lxon.connect(owner).mintEmission(ethers.parseEther("1000"));
      }

      // Get storage slots used (simplified measurement)
      const totalSupply = await lxon.totalSupply();
      console.log(`Total supply after ${numMints} mints: ${totalSupply.toString()}`);

      expect(totalSupply).to.equal(ethers.parseEther("1000000") + ethers.parseEther("1000") * BigInt(numMints));
    });
  });

  describe("Scalability Tests", () => {
    it("Should handle high volume of transfers", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("100000000"));

      const numTransfers = 1000;
      const transferAmount = ethers.parseEther("100");

      const startTime = Date.now();
      for (let i = 0; i < numTransfers; i++) {
        await lxon.transfer(user1.address, transferAmount);
      }
      const endTime = Date.now();

      const executionTime = endTime - startTime;
      const tps = (numTransfers / executionTime) * 1000; // transactions per second

      console.log(`High volume transfers: ${numTransfers} in ${executionTime}ms`);
      console.log(`Throughput: ${tps.toFixed(2)} TPS`);

      // Target: >10 TPS
      expect(tps).to.be.greaterThan(10);
    });

    it("Should handle large token amounts", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);

      const largeAmount = ethers.parseEther("100000000"); // 100 million tokens
      const tx = await lxon.connect(owner).mintEmission(largeAmount);
      const receipt = await tx.wait();
      if (!receipt) throw new Error("No receipt");

      const gasUsed = receipt.gasUsed;
      console.log(`Large amount mint gas cost: ${gasUsed.toString()}`);

      // Gas cost should not increase significantly with amount
      expect(gasUsed).to.be.lessThan(TARGETS.mintEmission * 2);
    });
  });

  describe("Optimization Opportunities", () => {
    it("Should identify gas optimization opportunities", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));

      // Compare gas costs for different operations
      await lxon.approve(owner.address, ethers.parseEther("100"));
      const operations = [
        { name: "transfer", fn: () => lxon.transfer(user1.address, ethers.parseEther("100")) },
        { name: "approve", fn: () => lxon.approve(user1.address, ethers.parseEther("100")) },
        { name: "transferFrom", fn: () => lxon.connect(user1).transferFrom(owner.address, user2.address, ethers.parseEther("100")) },
      ];

      for (const op of operations) {
        await lxon.grantRole(MINTER_ROLE, owner.address);
        const tx = await op.fn();
        const receipt = await tx.wait();
        if (!receipt) throw new Error("No receipt");

        console.log(`${op.name} gas cost: ${receipt.gasUsed.toString()}`);
      }
    });
  });
});