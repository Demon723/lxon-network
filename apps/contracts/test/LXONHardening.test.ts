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

describe("LXON Token Hardening - Milestone 0", () => {
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

  // Constants
  const TIMELOCK_DELAY = 172800; // 48 hours
  const MAX_SUPPLY = ethers.parseEther("1000000000");
  const INITIAL_AMOUNT = ethers.parseEther("100000");
  const MINTER_ROLE = ethers.id("MINTER_ROLE");
  const BURNER_ROLE = ethers.id("BURNER_ROLE");

  beforeEach(async () => {
    [owner, governance, user1, user2, treasury] = await ethers.getSigners();

    // Deploy LXON hardened token
    const LXONFactory = await ethers.getContractFactory("LXONHardened");
    lxon = await LXONFactory.deploy(governance.address, TIMELOCK_DELAY);
    await lxon.waitForDeployment();

    // Get timelock address from token
    timelock = await ethers.getContractAt(
      "TimelockController",
      await lxon.timelock()
    );

    // Deploy staking contract
    const StakingFactory = await ethers.getContractFactory(
      "LXONStakingHardened"
    );
    staking = await StakingFactory.deploy(
      await lxon.getAddress(),
      governance.address,
      TIMELOCK_DELAY
    );
    await staking.waitForDeployment();

    // Deploy vesting escrow
    const VestingFactory = await ethers.getContractFactory("VestingEscrow");
    vesting = await VestingFactory.deploy(await lxon.getAddress());
    await vesting.waitForDeployment();

    // Deploy governance (this will be done after testing token individually)
  });

  // ============ LXON Token Tests ============

  describe("LXONHardened Token", () => {
    it("Should have zero initial supply", async () => {
      const totalSupply = await lxon.totalSupply();
      expect(totalSupply).to.equal(0);
    });

    it("Should have MAX_SUPPLY constant set correctly", async () => {
      const maxSupply = await lxon.MAX_SUPPLY();
      expect(maxSupply).to.equal(MAX_SUPPLY);
    });

    it("Should have immutable governance address", async () => {
      const govAddress = await lxon.governance();
      expect(govAddress).to.equal(governance.address);
    });

    it("Should grant MINTER_ROLE to timelock", async () => {
      const hasRole = await lxon.hasRole(MINTER_ROLE, await lxon.timelock());
      expect(hasRole).to.be.true;
    });

    it("Should grant BURNER_ROLE to timelock", async () => {
      const hasRole = await lxon.hasRole(BURNER_ROLE, await lxon.timelock());
      expect(hasRole).to.be.true;
    });

    describe("mintEmission", () => {
      it("Should allow MINTER_ROLE to mint via timelock", async () => {
        const amount = ethers.parseEther("1000000");

        // Call mintEmission directly as owner (simulating timelock in tests)
        // In production, this goes through Governor -> Timelock
        await lxon.connect(governance).grantRole(MINTER_ROLE, owner.address);
        await lxon.connect(owner).mintEmission(amount);

        const totalSupply = await lxon.totalSupply();
        expect(totalSupply).to.equal(amount);
      });

      it("Should emit EmissionMinted event", async () => {
        const amount = ethers.parseEther("1000000");
        await lxon.connect(governance).grantRole(MINTER_ROLE, owner.address);

        await expect(lxon.connect(owner).mintEmission(amount))
          .to.emit(lxon, "EmissionMinted")
          .withArgs(amount, owner.address);
      });

      it("Should reject minting zero amount", async () => {
        await lxon.connect(governance).grantRole(MINTER_ROLE, owner.address);
        await expect(lxon.connect(owner).mintEmission(0)).to.be.revertedWith(
          "LXONHardened: amount must be > 0"
        );
      });

      it("Should reject minting beyond MAX_SUPPLY", async () => {
        await lxon.connect(governance).grantRole(MINTER_ROLE, owner.address);
        const overLimit = MAX_SUPPLY + ethers.parseEther("1");

        await expect(
          lxon.connect(owner).mintEmission(overLimit)
        ).to.be.revertedWith("LXONHardened: exceeds MAX_SUPPLY");
      });

      it("Should prevent unauthorized mint", async () => {
        const amount = ethers.parseEther("1000");

        await expect(
          lxon.connect(user1).mintEmission(amount)
        ).to.be.revertedWithCustomError(lxon, "AccessControlUnauthorizedAccount");
      });
    });

    describe("Burning", () => {
      beforeEach(async () => {
        // Mint some tokens for testing
        await lxon.connect(governance).grantRole(MINTER_ROLE, owner.address);
        await lxon.connect(owner).mintEmission(ethers.parseEther("1000000"));

        // Transfer to users
        await lxon.transfer(user1.address, ethers.parseEther("100000"));
        await lxon.transfer(user2.address, ethers.parseEther("100000"));
      });

      it("Should allow users to burn their own tokens", async () => {
        const burnAmount = ethers.parseEther("1000");
        const balanceBefore = await lxon.balanceOf(user1.address);

        await lxon.connect(user1).burn(burnAmount);

        const balanceAfter = await lxon.balanceOf(user1.address);
        expect(balanceAfter).to.equal(balanceBefore - burnAmount);
      });

      it("Should allow governance to burn treasury surplus", async () => {
        await lxon.connect(governance).grantRole(BURNER_ROLE, owner.address);
        const amount = ethers.parseEther("1000");

        await lxon.connect(owner).burnFromGovernance(user1.address, amount);

        const balance = await lxon.balanceOf(user1.address);
        expect(balance).to.equal(ethers.parseEther("100000") - amount);
      });

      it("Should prevent unauthorized governance burn", async () => {
        const amount = ethers.parseEther("1000");

        await expect(
          lxon.connect(user2).burnFromGovernance(user1.address, amount)
        ).to.be.revertedWithCustomError(lxon, "AccessControlUnauthorizedAccount");
      });

      it("Should emit TreasuryBurned event", async () => {
        await lxon.connect(governance).grantRole(BURNER_ROLE, owner.address);
        const amount = ethers.parseEther("1000");

        await expect(
          lxon.connect(owner).burnFromGovernance(user1.address, amount)
        )
          .to.emit(lxon, "TreasuryBurned")
          .withArgs(user1.address, amount, owner.address);
      });
    });

    describe("View Functions", () => {
      beforeEach(async () => {
        await lxon.connect(governance).grantRole(MINTER_ROLE, owner.address);
        await lxon.connect(owner).mintEmission(ethers.parseEther("500000000"));
      });

      it("Should calculate available to mint correctly", async () => {
        const available = await lxon.availableToMint();
        expect(available).to.equal(ethers.parseEther("500000000"));
      });

      it("Should return circulating supply", async () => {
        const circulating = await lxon.circulating();
        expect(circulating).to.equal(ethers.parseEther("500000000"));
      });
    });
  });

  // ============ Staking Tests ============

  describe("LXONStakingHardened", () => {
    const SUBNET_ID = ethers.id("contract-analysis");
    const LOCK_DURATION = 30 * 24 * 60 * 60; // 30 days

    beforeEach(async () => {
      // Mint tokens for staking
      await lxon.connect(governance).grantRole(MINTER_ROLE, owner.address);
      await lxon
        .connect(owner)
        .mintEmission(ethers.parseEther("10000000"));

      // Transfer to users
      await lxon.transfer(user1.address, ethers.parseEther("1000000"));
      await lxon.transfer(user2.address, ethers.parseEther("1000000"));

      // Approve staking contract
      await lxon
        .connect(user1)
        .approve(
          await staking.getAddress(),
          ethers.parseEther("1000000")
        );
      await lxon
        .connect(user2)
        .approve(
          await staking.getAddress(),
          ethers.parseEther("1000000")
        );

      // Create a subnet
      await staking.connect(governance).grantRole(
        ethers.id("SUBNET_MANAGER_ROLE"),
        owner.address
      );
      await staking.connect(owner).createSubnet(SUBNET_ID, 5000); // 50% weight
    });

    it("Should create a subnet", async () => {
      const subnet = await staking.subnets(SUBNET_ID);
      expect(subnet.active).to.be.true;
      expect(subnet.weight).to.equal(5000);
    });

    it("Should allow staking", async () => {
      const stakeAmount = ethers.parseEther("10000");

      await staking
        .connect(user1)
        .stake(stakeAmount, SUBNET_ID, LOCK_DURATION);

      const subnet = await staking.subnets(SUBNET_ID);
      expect(subnet.totalStaked).to.equal(stakeAmount);
    });

    it("Should emit Staked event", async () => {
      const stakeAmount = ethers.parseEther("10000");

      await expect(
        staking
          .connect(user1)
          .stake(stakeAmount, SUBNET_ID, LOCK_DURATION)
      )
        .to.emit(staking, "Staked")
        .withArgs(user1.address, stakeAmount, SUBNET_ID, LOCK_DURATION);
    });

    it("Should prevent staking below minimum", async () => {
      const minStake = await staking.MIN_STAKE();
      const belowMin = minStake - BigInt(1);

      await expect(
        staking.connect(user1).stake(belowMin, SUBNET_ID, LOCK_DURATION)
      ).to.be.revertedWith("LXONStakingHardened: amount below minimum");
    });

    it("Should prevent unstaking before lock period", async () => {
      const stakeAmount = ethers.parseEther("10000");

      await staking
        .connect(user1)
        .stake(stakeAmount, SUBNET_ID, LOCK_DURATION);

      await expect(staking.connect(user1).unstake(0)).to.be.revertedWith(
        "LXONStakingHardened: tokens locked"
      );
    });

    it("Should allow unstaking after lock period", async () => {
      const stakeAmount = ethers.parseEther("10000");

      await staking
        .connect(user1)
        .stake(stakeAmount, SUBNET_ID, LOCK_DURATION);

      // Fast forward time
      await ethers.provider.send("evm_increaseTime", [LOCK_DURATION + 1]);
      await ethers.provider.send("evm_mine", []);

      await staking.connect(user1).unstake(0);

      const balance = await lxon.balanceOf(user1.address);
      expect(balance).to.equal(ethers.parseEther("1000000"));
    });

    it("Should calculate voting power correctly", async () => {
      const stakeAmount = ethers.parseEther("50000");

      await staking
        .connect(user1)
        .stake(stakeAmount, SUBNET_ID, LOCK_DURATION);

      const votingPower = await staking.getVotingPower(user1.address);
      expect(votingPower).to.equal(stakeAmount);
    });

    it("Should calculate subnet weight", async () => {
      const amount1 = ethers.parseEther("10000");
      const amount2 = ethers.parseEther("20000");

      await staking
        .connect(user1)
        .stake(amount1, SUBNET_ID, LOCK_DURATION);
      await staking
        .connect(user2)
        .stake(amount2, SUBNET_ID, LOCK_DURATION);

      const weight = await staking.getSubnetWeight(SUBNET_ID);
      expect(weight).to.be.greaterThan(0);
      expect(weight).to.be.lessThanOrEqual(10000);
    });

    it("Should decommission subnet with zero stake", async () => {
      // Decommission should work if no stake
      const emptySubnet = ethers.id("empty-subnet");
      await staking.connect(owner).createSubnet(emptySubnet, 1000);

      await staking.connect(owner).decommissionSubnet(emptySubnet);

      const subnet = await staking.subnets(emptySubnet);
      expect(subnet.active).to.be.false;
    });

    it("Should prevent unstaking from non-existent schedule", async () => {
      await expect(staking.connect(user1).unstake(0)).to.be.revertedWith(
        "LXONStakingHardened: invalid index"
      );
    });
  });

  // ============ Vesting Escrow Tests ============

  describe("VestingEscrow", () => {
    const VESTING_AMOUNT = ethers.parseEther("1000000");
    const CLIFF_DURATION = 365 * 24 * 60 * 60; // 1 year
    const VESTING_DURATION = 4 * 365 * 24 * 60 * 60; // 4 years

    beforeEach(async () => {
      // Mint tokens for vesting
      await lxon.connect(governance).grantRole(MINTER_ROLE, owner.address);
      await lxon
        .connect(owner)
        .mintEmission(ethers.parseEther("10000000"));

      // Approve vesting contract
      await lxon
        .connect(owner)
        .approve(await vesting.getAddress(), VESTING_AMOUNT);
    });

    it("Should create vesting schedule", async () => {
      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600; // 1 hour from now

      const tx = await vesting
        .connect(owner)
        .createVestingSchedule(
          user1.address,
          VESTING_AMOUNT,
          startTime,
          CLIFF_DURATION,
          VESTING_DURATION,
          true
        );

      await tx.wait();

      const scheduleCount = await vesting.getScheduleCount();
      expect(scheduleCount).to.equal(1);
    });

    it("Should emit VestingScheduleCreated event", async () => {
      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;

      await expect(
        vesting
          .connect(owner)
          .createVestingSchedule(
            user1.address,
            VESTING_AMOUNT,
            startTime,
            CLIFF_DURATION,
            VESTING_DURATION,
            true
          )
      ).to.emit(vesting, "VestingScheduleCreated");
    });

    it("Should prevent vesting to zero address", async () => {
      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;

      await expect(
        vesting
          .connect(owner)
          .createVestingSchedule(
            ethers.ZeroAddress,
            VESTING_AMOUNT,
            startTime,
            CLIFF_DURATION,
            VESTING_DURATION,
            true
          )
      ).to.be.revertedWith("VestingEscrow: invalid beneficiary");
    });

    it("Should prevent cliff > duration", async () => {
      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;

      await expect(
        vesting
          .connect(owner)
          .createVestingSchedule(
            user1.address,
            VESTING_AMOUNT,
            startTime,
            VESTING_DURATION + 1, // cliff > duration
            VESTING_DURATION,
            true
          )
      ).to.be.revertedWith("VestingEscrow: cliff > duration");
    });

    it("Should calculate releasable amount correctly", async () => {
      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;

      const tx = await vesting
        .connect(owner)
        .createVestingSchedule(
          user1.address,
          VESTING_AMOUNT,
          startTime,
          CLIFF_DURATION,
          VESTING_DURATION,
          true
        );

      const receipt = await tx.wait();
      if (!receipt) throw new Error("No receipt");

      // Get schedule ID from event
      const scheduleId = (await vesting.getBeneficiarySchedules(user1.address))[0];

      // Before cliff, nothing releasable
      let releasable = await vesting.getReleasableAmount(scheduleId);
      expect(releasable).to.equal(0);

      // Fast forward past cliff (startTime is 3600s in the future)
      await ethers.provider.send("evm_increaseTime", [3600 + CLIFF_DURATION + 1]);
      await ethers.provider.send("evm_mine", []);

      // After cliff, some tokens releasable
      releasable = await vesting.getReleasableAmount(scheduleId);
      expect(releasable).to.be.greaterThan(0);

      // Fast forward to end of vesting
      await ethers.provider.send("evm_increaseTime", [VESTING_DURATION]);
      await ethers.provider.send("evm_mine", []);

      // All tokens releasable at end
      releasable = await vesting.getReleasableAmount(scheduleId);
      expect(releasable).to.equal(VESTING_AMOUNT);
    });

    it("Should allow beneficiary to release tokens", async () => {
      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;

      const tx = await vesting
        .connect(owner)
        .createVestingSchedule(
          user1.address,
          VESTING_AMOUNT,
          startTime,
          CLIFF_DURATION,
          VESTING_DURATION,
          true
        );

      await tx.wait();

      const scheduleId = (await vesting.getBeneficiarySchedules(user1.address))[0];

      // Fast forward past cliff (startTime is 3600s in the future)
      await ethers.provider.send("evm_increaseTime", [3600 + CLIFF_DURATION + 1]);
      await ethers.provider.send("evm_mine", []);

      const balanceBefore = await lxon.balanceOf(user1.address);
      await vesting.connect(user1).release(scheduleId);
      const balanceAfter = await lxon.balanceOf(user1.address);

      expect(balanceAfter).to.be.greaterThan(balanceBefore);
    });

    it("Should allow revoking revocable schedule", async () => {
      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;

      const tx = await vesting
        .connect(owner)
        .createVestingSchedule(
          user1.address,
          VESTING_AMOUNT,
          startTime,
          CLIFF_DURATION,
          VESTING_DURATION,
          true // revocable
        );

      await tx.wait();

      const scheduleId = (await vesting.getBeneficiarySchedules(user1.address))[0];

      await vesting.connect(owner).revokeSchedule(scheduleId);

      const schedule = await vesting.getSchedule(scheduleId);
      expect(schedule.revoked).to.be.true;
    });

    it("Should prevent non-revocable schedule revocation", async () => {
      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;

      await vesting
        .connect(owner)
        .createVestingSchedule(
          user1.address,
          VESTING_AMOUNT,
          startTime,
          CLIFF_DURATION,
          VESTING_DURATION,
          false // not revocable
        );

      const scheduleId = (await vesting.getBeneficiarySchedules(user1.address))[0];

      await expect(
        vesting.connect(owner).revokeSchedule(scheduleId)
      ).to.be.revertedWith("VestingEscrow: not revocable");
    });

    it("Should emit TokensReleased event", async () => {
      const startTime = (await ethers.provider.getBlock("latest"))!.timestamp + 3600;

      const tx = await vesting
        .connect(owner)
        .createVestingSchedule(
          user1.address,
          VESTING_AMOUNT,
          startTime,
          CLIFF_DURATION,
          VESTING_DURATION,
          true
        );

      await tx.wait();

      const scheduleId = (await vesting.getBeneficiarySchedules(user1.address))[0];

      // Fast forward past cliff (startTime is 3600s in the future)
      await ethers.provider.send("evm_increaseTime", [3600 + CLIFF_DURATION + 1]);
      await ethers.provider.send("evm_mine", []);

      await expect(vesting.connect(user1).release(scheduleId)).to.emit(
        vesting,
        "TokensReleased"
      );
    });
  });

  // ============ Integration Tests ============

  describe("Integration Tests", () => {
    it("Should complete full emission and staking flow", async () => {
      const SUBNET_ID = ethers.id("integration-test");
      const STAKE_AMOUNT = ethers.parseEther("100000");
      const EMISSION_AMOUNT = ethers.parseEther("1000000");

      // 1. Mint emissions
      await lxon.connect(governance).grantRole(MINTER_ROLE, owner.address);
      await lxon.connect(owner).mintEmission(EMISSION_AMOUNT);

      // 2. Transfer to users
      await lxon.transfer(user1.address, STAKE_AMOUNT);
      await lxon
        .connect(user1)
        .approve(await staking.getAddress(), STAKE_AMOUNT);

      // 3. Create subnet
      await staking.connect(governance).grantRole(
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

    it("Should complete full vesting and token burn flow", async () => {
      const VESTING_AMOUNT = ethers.parseEther("1000000");
      const BURN_AMOUNT = ethers.parseEther("100000");
      const CLIFF = 365 * 24 * 60 * 60;
      const DURATION = 4 * 365 * 24 * 60 * 60;

      // 1. Mint tokens
      await lxon.connect(governance).grantRole(MINTER_ROLE, owner.address);
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

      // 3. Burn some tokens
      await lxon.connect(governance).grantRole(BURNER_ROLE, owner.address);
      await lxon.transfer(user2.address, BURN_AMOUNT);
      await lxon.connect(user2).burn(BURN_AMOUNT);

      // 4. Fast forward past cliff (startTime is 3600s in the future)
      await ethers.provider.send("evm_increaseTime", [3600 + CLIFF + 1]);
      await ethers.provider.send("evm_mine", []);

      const scheduleId = (await vesting.getBeneficiarySchedules(user1.address))[0];
      await vesting.connect(user1).release(scheduleId);

      // 5. Verify final state
      const totalSupply = await lxon.totalSupply();
      const user1Balance = await lxon.balanceOf(user1.address);

      expect(totalSupply).to.equal(ethers.parseEther("2000000") - BURN_AMOUNT);
      expect(user1Balance).to.be.greaterThan(0);
    });
  });
});
