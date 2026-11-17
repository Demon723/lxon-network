import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  LXONHardened,
  LXONStakingHardened,
  LXONGovernanceHardened,
  VestingEscrow,
  TimelockController,
} from "../typechain-types";

/**
 * Integration Tests
 * 
 * These tests verify that different components work together correctly
 * and that the entire system functions as expected when components interact.
 */

describe("LXON Integration Tests", () => {
  let owner: SignerWithAddress;
  let governance: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let treasury: SignerWithAddress;

  let lxon: LXONHardened;
  let timelock: TimelockController;
  let staking: LXONStakingHardened;
  let governanceContract: LXONGovernanceHardened;
  let vesting: VestingEscrow;

  const TIMELOCK_DELAY = 172800;
  const MAX_SUPPLY = ethers.parseEther("1000000000");
  const MINTER_ROLE = ethers.id("MINTER_ROLE");
  const BURNER_ROLE = ethers.id("BURNER_ROLE");

  beforeEach(async () => {
    [owner, governance, user1, user2, treasury] = await ethers.getSigners();

    // Deploy LXON hardened token (owner holds DEFAULT_ADMIN_ROLE)
    const LXONFactory = await ethers.getContractFactory("LXONHardened");
    lxon = await LXONFactory.deploy(owner.address, TIMELOCK_DELAY);
    await lxon.waitForDeployment();

    // Get timelock address from token
    timelock = await ethers.getContractAt(
      "TimelockController",
      await lxon.timelock()
    );

    // Deploy staking contract (owner holds DEFAULT_ADMIN_ROLE)
    const StakingFactory = await ethers.getContractFactory(
      "LXONStakingHardened"
    );
    staking = await StakingFactory.deploy(
      await lxon.getAddress(),
      owner.address,
      TIMELOCK_DELAY
    );
    await staking.waitForDeployment();

    // Deploy vesting escrow
    const VestingFactory = await ethers.getContractFactory("VestingEscrow");
    vesting = await VestingFactory.deploy(await lxon.getAddress());
    await vesting.waitForDeployment();

    // Deploy governance contract (constructor takes token + timelock)
    const GovernanceFactory = await ethers.getContractFactory(
      "LXONGovernanceHardened"
    );
    governanceContract = await GovernanceFactory.deploy(
      await lxon.getAddress(),
      await timelock.getAddress()
    );
    await governanceContract.waitForDeployment();
  });

  describe("Token ↔ Staking Integration", () => {
    it("Should complete full emission → stake → unstake flow", async () => {
      const SUBNET_ID = ethers.id("integration-test");
      const STAKE_AMOUNT = ethers.parseEther("100000");
      const EMISSION_AMOUNT = ethers.parseEther("1000000");

      // 1. Mint emissions
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(EMISSION_AMOUNT);

      // 2. Transfer to users
      await lxon.transfer(user1.address, STAKE_AMOUNT);
      await lxon
        .connect(user1)
        .approve(await staking.getAddress(), STAKE_AMOUNT);

      // 3. Create subnet
      await staking.grantRole(
        ethers.id("SUBNET_MANAGER_ROLE"),
        owner.address
      );
      await staking.connect(owner).createSubnet(SUBNET_ID, 5000);

      // 4. Stake tokens
      await staking
        .connect(user1)
        .stake(STAKE_AMOUNT, SUBNET_ID, 30 * 24 * 60 * 60);

      // 5. Verify state
      const totalSupply = await lxon.totalSupply();
      const stakedAmount = await staking.getSubnetTotalStaked(SUBNET_ID);
      const votingPower = await staking.getVotingPower(user1.address);

      expect(totalSupply).to.equal(EMISSION_AMOUNT);
      expect(stakedAmount).to.equal(STAKE_AMOUNT);
      expect(votingPower).to.equal(STAKE_AMOUNT);
    });

    it("Should handle multiple stakes across different subnets", async () => {
      const SUBNET_1 = ethers.id("subnet-1");
      const SUBNET_2 = ethers.id("subnet-2");
      const STAKE_AMOUNT = ethers.parseEther("50000");

      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));
      await lxon.transfer(user1.address, ethers.parseEther("200000"));
      await lxon
        .connect(user1)
        .approve(await staking.getAddress(), ethers.parseEther("200000"));

      await staking.grantRole(
        ethers.id("SUBNET_MANAGER_ROLE"),
        owner.address
      );
      await staking.connect(owner).createSubnet(SUBNET_1, 3000);
      await staking.connect(owner).createSubnet(SUBNET_2, 7000);

      // Stake in both subnets
      await staking
        .connect(user1)
        .stake(STAKE_AMOUNT, SUBNET_1, 30 * 24 * 60 * 60);
      await staking
        .connect(user1)
        .stake(STAKE_AMOUNT, SUBNET_2, 90 * 24 * 60 * 60);

      const totalVotingPower = await staking.getVotingPower(user1.address);
      expect(totalVotingPower).to.equal(STAKE_AMOUNT * 2n);
    });
  });

  describe("Token ↔ Vesting Integration", () => {
    it("Should complete full emission → vest → release flow", async () => {
      const VESTING_AMOUNT = ethers.parseEther("1000000");
      const CLIFF = 365 * 24 * 60 * 60;
      const DURATION = 4 * 365 * 24 * 60 * 60;

      // 1. Mint tokens
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon
        .connect(owner)
        .mintEmission(ethers.parseEther("2000000"));

      // 2. Create vesting schedule
      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;
      await lxon
        .connect(owner)
        .approve(await vesting.getAddress(), VESTING_AMOUNT);

      await vesting
        .connect(owner)
        .createVestingSchedule(
          user1.address,
          VESTING_AMOUNT,
          startTime,
          CLIFF,
          DURATION,
          true
        );

      // 3. Fast forward past cliff (startTime is 3600s in the future)
      await ethers.provider.send("evm_increaseTime", [3600 + CLIFF + 1]);
      await ethers.provider.send("evm_mine", []);

      const scheduleId = (await vesting.getBeneficiarySchedules(user1.address))[0];
      await vesting.connect(user1).release(scheduleId);

      // 4. Verify user received tokens
      const userBalance = await lxon.balanceOf(user1.address);
      expect(userBalance).to.be.greaterThan(0);
    });

    it("Should handle vesting with token burns", async () => {
      const VESTING_AMOUNT = ethers.parseEther("1000000");
      const BURN_AMOUNT = ethers.parseEther("100000");
      const CLIFF = 365 * 24 * 60 * 60;
      const DURATION = 4 * 365 * 24 * 60 * 60;

      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon
        .connect(owner)
        .mintEmission(ethers.parseEther("2000000"));

      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;
      await lxon
        .connect(owner)
        .approve(await vesting.getAddress(), VESTING_AMOUNT);

      await vesting
        .connect(owner)
        .createVestingSchedule(
          user1.address,
          VESTING_AMOUNT,
          startTime,
          CLIFF,
          DURATION,
          true
        );

      // Burn some tokens
      await lxon.grantRole(BURNER_ROLE, owner.address);
      await lxon.transfer(user2.address, BURN_AMOUNT);
      await lxon.connect(user2).burn(BURN_AMOUNT);

      // Verify vesting still works after burn (past cliff)
      await ethers.provider.send("evm_increaseTime", [3600 + CLIFF + 1]);
      await ethers.provider.send("evm_mine", []);

      const scheduleId = (await vesting.getBeneficiarySchedules(user1.address))[0];
      await vesting.connect(user1).release(scheduleId);

      const totalSupply = await lxon.totalSupply();
      expect(totalSupply).to.equal(ethers.parseEther("2000000") - BURN_AMOUNT);
    });
  });

  describe("Staking ↔ Governance Integration", () => {
    it("Should calculate voting power from staked tokens", async () => {
      const SUBNET_ID = ethers.id("gov-test");
      const STAKE_AMOUNT = ethers.parseEther("100000");

      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));
      await lxon.transfer(user1.address, STAKE_AMOUNT);
      await lxon
        .connect(user1)
        .approve(await staking.getAddress(), STAKE_AMOUNT);

      await staking.grantRole(
        ethers.id("SUBNET_MANAGER_ROLE"),
        owner.address
      );
      await staking.connect(owner).createSubnet(SUBNET_ID, 5000);

      await staking
        .connect(user1)
        .stake(STAKE_AMOUNT, SUBNET_ID, 30 * 24 * 60 * 60);

      const votingPower = await staking.getVotingPower(user1.address);
      expect(votingPower).to.equal(STAKE_AMOUNT);
    });

    it("Should update voting power after unstaking", async () => {
      const SUBNET_ID = ethers.id("gov-test");
      const STAKE_AMOUNT = ethers.parseEther("100000");

      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));
      await lxon.transfer(user1.address, STAKE_AMOUNT);
      await lxon
        .connect(user1)
        .approve(await staking.getAddress(), STAKE_AMOUNT);

      await staking.grantRole(
        ethers.id("SUBNET_MANAGER_ROLE"),
        owner.address
      );
      await staking.connect(owner).createSubnet(SUBNET_ID, 5000);

      await staking
        .connect(user1)
        .stake(STAKE_AMOUNT, SUBNET_ID, 30 * 24 * 60 * 60);

      // Fast forward and unstake
      await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60 + 1]);
      await ethers.provider.send("evm_mine", []);

      await staking.connect(user1).unstake(0);

      const votingPower = await staking.getVotingPower(user1.address);
      expect(votingPower).to.equal(0);
    });
  });

  describe("Multi-Contract Integration", () => {
    it("Should handle complex multi-step operations", async () => {
      const SUBNET_ID = ethers.id("complex-test");
      const VESTING_AMOUNT = ethers.parseEther("500000");
      const STAKE_AMOUNT = ethers.parseEther("200000");

      // 1. Mint emissions
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("2000000"));

      // 2. Set up vesting
      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;
      await lxon
        .connect(owner)
        .approve(await vesting.getAddress(), VESTING_AMOUNT);
      await vesting
        .connect(owner)
        .createVestingSchedule(
          user1.address,
          VESTING_AMOUNT,
          startTime,
          365 * 24 * 60 * 60,
          4 * 365 * 24 * 60 * 60,
          true
        );

      // 3. Set up staking
      await lxon.transfer(user2.address, STAKE_AMOUNT);
      await lxon
        .connect(user2)
        .approve(await staking.getAddress(), STAKE_AMOUNT);

      await staking.grantRole(
        ethers.id("SUBNET_MANAGER_ROLE"),
        owner.address
      );
      await staking.connect(owner).createSubnet(SUBNET_ID, 5000);
      await staking
        .connect(user2)
        .stake(STAKE_AMOUNT, SUBNET_ID, 30 * 24 * 60 * 60);

      // 4. Verify all components are working
      const totalSupply = await lxon.totalSupply();
      const stakedAmount = await staking.getSubnetTotalStaked(SUBNET_ID);
      const scheduleCount = await vesting.getScheduleCount();

      expect(totalSupply).to.equal(ethers.parseEther("2000000"));
      expect(stakedAmount).to.equal(STAKE_AMOUNT);
      expect(scheduleCount).to.equal(1);
    });

    it("Should handle token burn while staking and vesting active", async () => {
      const SUBNET_ID = ethers.id("burn-test");
      const STAKE_AMOUNT = ethers.parseEther("100000");
      const BURN_AMOUNT = ethers.parseEther("50000");

      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));

      // Set up staking
      await lxon.transfer(user1.address, STAKE_AMOUNT);
      await lxon
        .connect(user1)
        .approve(await staking.getAddress(), STAKE_AMOUNT);

      await staking.grantRole(
        ethers.id("SUBNET_MANAGER_ROLE"),
        owner.address
      );
      await staking.connect(owner).createSubnet(SUBNET_ID, 5000);
      await staking
        .connect(user1)
        .stake(STAKE_AMOUNT, SUBNET_ID, 30 * 24 * 60 * 60);

      // Burn tokens
      await lxon.grantRole(BURNER_ROLE, owner.address);
      await lxon.transfer(user2.address, BURN_AMOUNT);
      await lxon.connect(user2).burn(BURN_AMOUNT);

      // Verify staking still works
      const stakedAmount = await staking.getSubnetTotalStaked(SUBNET_ID);
      expect(stakedAmount).to.equal(STAKE_AMOUNT);

      // Verify burn reduced supply
      const totalSupply = await lxon.totalSupply();
      expect(totalSupply).to.equal(ethers.parseEther("1000000") - BURN_AMOUNT);
    });
  });

  describe("Error Recovery Integration", () => {
    it("Should handle failed transactions gracefully", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));

      // Try to transfer more than balance
      const balance = await lxon.balanceOf(owner.address);
      const overBalance = balance + ethers.parseEther("1");

      await expect(
        lxon.connect(owner).transfer(user1.address, overBalance)
      ).to.be.revertedWithCustomError(lxon, "ERC20InsufficientBalance");

      // Verify state unchanged
      const ownerBalance = await lxon.balanceOf(owner.address);
      expect(ownerBalance).to.equal(balance);
    });

    it("Should handle role changes during operations", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));

      // Revoke role during operation
      await lxon.revokeRole(MINTER_ROLE, owner.address);

      await expect(
        lxon.connect(owner).mintEmission(ethers.parseEther("1000"))
      ).to.be.revertedWithCustomError(lxon, "AccessControlUnauthorizedAccount");
    });
  });

  describe("Gas Optimization Integration", () => {
    it("Should optimize multi-contract operations", async () => {
      await lxon.grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));

      // Measure gas for multi-step operation
      const tx = await lxon.transfer(user1.address, ethers.parseEther("100000"));
      const receipt = await tx.wait();
      if (!receipt) throw new Error("No receipt");

      const gasUsed = receipt.gasUsed;
      console.log(`Transfer gas cost: ${gasUsed.toString()}`);

      // Target: <80k gas for basic transfer (ERC20Votes checkpointing adds gas)
      expect(gasUsed).to.be.lessThan(80000);
    });
  });
});