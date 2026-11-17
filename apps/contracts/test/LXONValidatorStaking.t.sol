// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/LXON.sol";
import "../contracts/LXONValidatorStaking.sol";

contract LXONValidatorStakingTest is Test {
    LXON public lxonToken;
    LXONValidatorStaking public validatorStaking;

    address public owner;
    address public validator1;
    address public validator2;
    address public validator3;

    uint256 public constant TIER_1_STAKE = 10_000 * 1e4;  // 10,000 LXON tokens (1 USD cent)
    uint256 public constant TIER_2_STAKE = 50_000 * 1e4;  // 50,000 LXON tokens (5 USD cents)
    uint256 public constant TIER_3_STAKE = 500_000 * 1e4;  // 500,000 LXON tokens (50 USD cents)

    function setUp() public {
        owner = address(this);
        validator1 = address(0x1);
        validator2 = address(0x2);
        validator3 = address(0x3);

        // Deploy LXON token
        lxonToken = new LXON(owner);

        // Grant MINT_ROLE and ORACLE_ROLE to this contract
        lxonToken.grantRole(lxonToken.MINT_ROLE(), owner);
        lxonToken.grantRole(lxonToken.ORACLE_ROLE(), owner);

        // Set a high reserve ceiling
        lxonToken.updateCeiling(1_000_000_000, bytes32(0));  // 1 billion USD cents

        // Deploy validator staking contract (address(this) will be admin)
        validatorStaking = new LXONValidatorStaking(address(lxonToken), 2 days);

        // Mint tokens to validators (mint takes USD cents, multiplies by 1e4)
        // Each validator gets 500000 USD cents = 5,000,000,000 tokens (enough for Tier 3)
        lxonToken.mint(validator1, 500000, bytes32(0));
        lxonToken.mint(validator2, 500000, bytes32(0));
        lxonToken.mint(validator3, 500000, bytes32(0));

        // Approve staking contract
        vm.startPrank(validator1);
        lxonToken.approve(address(validatorStaking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(validator2);
        lxonToken.approve(address(validatorStaking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(validator3);
        lxonToken.approve(address(validatorStaking), type(uint256).max);
        vm.stopPrank();
    }

    function test_ValidatorStaking_Initialization() public {
        assertEq(address(validatorStaking.lxonToken()), address(lxonToken));
        assertEq(validatorStaking.getTotalValidators(), 0);
        assertEq(validatorStaking.getActiveValidators(), 0);
        assertEq(validatorStaking.totalStaked(), 0);
    }

    function test_ValidatorStaking_RegisterTier1() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_1_STAKE);
        vm.stopPrank();

        LXONValidatorStaking.ValidatorInfo memory info = validatorStaking.getValidatorInfo(validator1);

        assertEq(info.operator, validator1);
        assertEq(info.stakeAmount, TIER_1_STAKE);
        assertEq(info.tier, 1);
        assertEq(info.active, true);
        assertEq(info.uptimeScore, 10000);
        assertEq(info.slashCount, 0);
        assertEq(validatorStaking.getTotalValidators(), 1);
        assertEq(validatorStaking.getActiveValidators(), 1);
        assertEq(validatorStaking.totalStaked(), TIER_1_STAKE);
    }

    function test_ValidatorStaking_RegisterTier2() public {
        vm.startPrank(validator2);
        validatorStaking.registerValidator(TIER_2_STAKE);
        vm.stopPrank();

        LXONValidatorStaking.ValidatorInfo memory info = validatorStaking.getValidatorInfo(validator2);
        assertEq(info.tier, 2);
    }

    function test_ValidatorStaking_RegisterTier3() public {
        vm.startPrank(validator3);
        validatorStaking.registerValidator(TIER_3_STAKE);
        vm.stopPrank();

        LXONValidatorStaking.ValidatorInfo memory info = validatorStaking.getValidatorInfo(validator3);
        assertEq(info.tier, 3);
    }

    function test_ValidatorStaking_RegisterBelowMinimum() public {
        vm.startPrank(validator1);
        vm.expectRevert("LXONValidatorStaking: below minimum stake");
        validatorStaking.registerValidator(9999 * 1e4);
        vm.stopPrank();
    }

    function test_ValidatorStaking_RegisterTwice() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_1_STAKE);
        vm.expectRevert("LXONValidatorStaking: already registered");
        validatorStaking.registerValidator(TIER_1_STAKE);
        vm.stopPrank();
    }

    function test_ValidatorStaking_IncreaseStake() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_1_STAKE);
        validatorStaking.increaseStake(40_000 * 1e4);
        vm.stopPrank();

        LXONValidatorStaking.ValidatorInfo memory info = validatorStaking.getValidatorInfo(validator1);
        assertEq(info.stakeAmount, 50_000 * 1e4);
        assertEq(info.tier, 2);  // Tier upgrade
    }

    function test_ValidatorStaking_IncreaseStakeTierUpgrade() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_2_STAKE);
        validatorStaking.increaseStake(450_000 * 1e4);
        vm.stopPrank();

        LXONValidatorStaking.ValidatorInfo memory info = validatorStaking.getValidatorInfo(validator1);
        assertEq(info.tier, 3);  // Tier upgrade to Tier 3
    }

    function test_ValidatorStaking_DecreaseStake() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_2_STAKE);
        validatorStaking.decreaseStake(40_000 * 1e4);
        vm.stopPrank();

        LXONValidatorStaking.ValidatorInfo memory info = validatorStaking.getValidatorInfo(validator1);
        assertEq(info.stakeAmount, 10_000 * 1e4);
        assertEq(info.tier, 1);  // Tier downgrade
    }

    function test_ValidatorStaking_DecreaseStakeBelowMinimum() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_2_STAKE);
        vm.expectRevert("LXONValidatorStaking: below minimum after decrease");
        validatorStaking.decreaseStake(40_001 * 1e4);
        vm.stopPrank();
    }

    function test_ValidatorStaking_StartUnbonding() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_1_STAKE);
        validatorStaking.startUnbonding();
        vm.stopPrank();

        LXONValidatorStaking.ValidatorInfo memory info = validatorStaking.getValidatorInfo(validator1);
        assertEq(info.inUnbonding, true);
        assertEq(info.unbondingStartedAt, block.timestamp);
        assertEq(validatorStaking.getActiveValidators(), 0);
    }

    function test_ValidatorStaking_CompleteUnbondingTooEarly() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_1_STAKE);
        validatorStaking.startUnbonding();
        vm.stopPrank();

        vm.startPrank(validator1);
        vm.expectRevert("LXONValidatorStaking: unbonding period not elapsed");
        validatorStaking.completeUnbonding();
        vm.stopPrank();
    }

    function test_ValidatorStaking_CompleteUnbonding() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_1_STAKE);
        validatorStaking.startUnbonding();
        vm.stopPrank();

        // Fast forward 21 days
        vm.warp(block.timestamp + 21 days + 1);

        vm.startPrank(validator1);
        validatorStaking.completeUnbonding();
        vm.stopPrank();

        LXONValidatorStaking.ValidatorInfo memory info = validatorStaking.getValidatorInfo(validator1);
        assertEq(info.stakeAmount, 0);
        assertEq(info.active, false);
        assertEq(lxonToken.balanceOf(validator1), 500000 * 1e4);  // 5,000,000,000 tokens
    }

    function test_ValidatorStaking_CancelUnbonding() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_1_STAKE);
        validatorStaking.startUnbonding();
        validatorStaking.cancelUnbonding();
        vm.stopPrank();

        LXONValidatorStaking.ValidatorInfo memory info = validatorStaking.getValidatorInfo(validator1);
        assertEq(info.inUnbonding, false);
        assertEq(validatorStaking.getActiveValidators(), 1);
    }

    function test_ValidatorStaking_CalculateReward() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_1_STAKE);
        vm.stopPrank();

        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);

        uint256 reward = validatorStaking.calculateReward(validator1);
        assertGt(reward, 0);
    }

    function test_ValidatorStaking_CalculateRewardTier2() public {
        vm.startPrank(validator2);
        validatorStaking.registerValidator(TIER_2_STAKE);
        vm.stopPrank();

        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);

        uint256 reward1 = validatorStaking.calculateReward(validator1);
        uint256 reward2 = validatorStaking.calculateReward(validator2);
        assertGt(reward2, reward1);  // Tier 2 should have higher APY
    }

    function test_ValidatorStaking_CalculateRewardTier3() public {
        vm.startPrank(validator3);
        validatorStaking.registerValidator(TIER_3_STAKE);
        vm.stopPrank();

        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);

        uint256 reward1 = validatorStaking.calculateReward(validator1);
        uint256 reward3 = validatorStaking.calculateReward(validator3);
        assertGt(reward3, reward1);  // Tier 3 should have highest APY
    }

    function test_ValidatorStaking_GetValidatorsByTier() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_1_STAKE);
        vm.stopPrank();

        vm.startPrank(validator2);
        validatorStaking.registerValidator(TIER_2_STAKE);
        vm.stopPrank();

        vm.startPrank(validator3);
        validatorStaking.registerValidator(TIER_3_STAKE);
        vm.stopPrank();

        address[] memory tier1 = validatorStaking.getValidatorsByTier(1);
        address[] memory tier2 = validatorStaking.getValidatorsByTier(2);
        address[] memory tier3 = validatorStaking.getValidatorsByTier(3);

        assertEq(tier1.length, 1);
        assertEq(tier2.length, 1);
        assertEq(tier3.length, 1);
        assertEq(tier1[0], validator1);
        assertEq(tier2[0], validator2);
        assertEq(tier3[0], validator3);
    }

    function test_ValidatorStaking_GetAllValidators() public {
        vm.startPrank(validator1);
        validatorStaking.registerValidator(TIER_1_STAKE);
        vm.stopPrank();

        vm.startPrank(validator2);
        validatorStaking.registerValidator(TIER_2_STAKE);
        vm.stopPrank();

        address[] memory allValidators = validatorStaking.getAllValidators();
        assertEq(allValidators.length, 2);
    }
}
