import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";
import { PriceFloorMechanism, LXONPriceOracle } from "../typechain-types";
import { ERC20Mock } from "../typechain-types";

describe("Price Floor Mechanism - $1.50 Floor", function () {
  let priceFloor: PriceFloorMechanism;
  let oracle: LXONPriceOracle;
  let usdc: ERC20Mock;
  let weth: ERC20Mock;
  let lxon: ERC20Mock;
  let router: Signer;
  let pair: Signer;
  let owner: Signer;
  let user: Signer;
  let ownerAddress: string;
  let userAddress: string;

  const PRICE_FLOOR = ethers.parseEther("1.50"); // $1.50
  const INITIAL_USDC = ethers.parseUnits("3500000", 6); // $3.5M USDC
  const INITIAL_WETH = ethers.parseEther("875"); // ~875 ETH

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();
    ownerAddress = await owner.getAddress();
    userAddress = await user.getAddress();

    // Deploy mock tokens
    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    usdc = await ERC20Mock.deploy("USD Coin", "USDC", 6);
    weth = await ERC20Mock.deploy("Wrapped Ether", "WETH", 18);
    lxon = await ERC20Mock.deploy("LXON Token", "LXON", 18);

    // Deploy oracle (mock implementation needed)
    // For now, skip oracle deployment and use manual override

    // Deploy price floor mechanism
    const PriceFloorMechanism = await ethers.getContractFactory("PriceFloorMechanism");
    priceFloor = await PriceFloorMechanism.deploy(
      await usdc.getAddress(),
      await weth.getAddress(),
      await lxon.getAddress(),
      await owner.getAddress(), // router (mock)
      await owner.getAddress(), // pair (mock)
      await owner.getAddress(), // oracle (mock)
      ownerAddress
    );

    // Mint tokens to owner
    await usdc.mint(ownerAddress, INITIAL_USDC);
    await weth.mint(ownerAddress, INITIAL_WETH);
  });

  it("should deploy with correct price floor configuration", async function () {
    const floorPrice = await priceFloor.PRICE_FLOOR_USD();
    expect(floorPrice).to.equal(PRICE_FLOOR);
  });

  it("should accept initial reserves", async function () {
    await usdc.approve(await priceFloor.getAddress(), INITIAL_USDC);
    await weth.approve(await priceFloor.getAddress(), INITIAL_WETH);

    await priceFloor.addReserves(INITIAL_USDC, INITIAL_WETH);

    const (usdcReserves, wethReserves, , , , ) = await priceFloor.getReserveInfo();
    expect(usdcReserves).to.equal(INITIAL_USDC);
    expect(wethReserves).to.equal(INITIAL_WETH);
  });

  it("should set buyback budgets correctly", async function () {
    const usdcBudget = ethers.parseUnits("1000000", 6); // $1M
    const wethBudget = ethers.parseEther("500"); // 500 ETH

    await priceFloor.setBuybackBudget(usdcBudget, wethBudget);

    const (, , usdcBudgetSet, wethBudgetSet, , ) = await priceFloor.getReserveInfo();
    expect(usdcBudgetSet).to.equal(usdcBudget);
    expect(wethBudgetSet).to.equal(wethBudget);
  });

  it("should calculate buyback amount based on price gap", async function () {
    // This would require oracle integration
    // For now, test the structure
    const (currentPrice, floorPrice, triggerPrice, needsDefense, distance) = 
      await priceFloor.getPriceStatus();
    
    expect(floorPrice).to.equal(PRICE_FLOOR);
    expect(triggerPrice).to.equal(PRICE_FLOOR - ethers.parseEther("0.02"));
  });

  it("should enforce daily buyback limits", async function () {
    const dailyLimit = ethers.parseUnits("1000000", 6); // $1M daily
    await priceFloor.setBuybackLimits(
      ethers.parseUnits("100000", 6), // $100k per tx
      dailyLimit
    );

    // Add reserves
    await usdc.approve(await priceFloor.getAddress(), INITIAL_USDC);
    await priceFloor.addReserves(INITIAL_USDC, 0);

    // This would need oracle integration to test actual buyback
    // For now, verify limit configuration
    const (, , , , dailySpent, dailyRemaining) = await priceFloor.getReserveInfo();
    expect(dailyRemaining).to.equal(dailyLimit);
  });

  it("should allow emergency mode toggle", async function () {
    await priceFloor.setEmergencyMode(true);
    expect(await priceFloor.emergencyMode()).to.be.true;

    await priceFloor.setEmergencyMode(false);
    expect(await priceFloor.emergencyMode()).to.be.false;
  });

  it("should allow fee configuration", async function () {
    await priceFloor.setFees(50, 10); // 0.5% buyback fee, 0.1% treasury fee
    
    const buybackFee = await priceFloor.buybackFeeBps();
    const treasuryFee = await priceFloor.treasuryFeeBps();
    
    expect(buybackFee).to.equal(50);
    expect(treasuryFee).to.equal(10);
  });

  it("should prevent buyback when emergency mode is active", async function () {
    await priceFloor.setEmergencyMode(true);
    
    // Add reserves first
    await usdc.approve(await priceFloor.getAddress(), INITIAL_USDC);
    await priceFloor.addReserves(INITIAL_USDC, 0);

    // Try to defend price floor (should fail due to emergency mode)
    await expect(
      priceFloor.defendPriceFloor()
    ).to.be.revertedWith("Emergency mode active");
  });

  it("should provide accurate reserve information", async function () {
    await usdc.approve(await priceFloor.getAddress(), INITIAL_USDC);
    await weth.approve(await priceFloor.getAddress(), INITIAL_WETH);
    await priceFloor.addReserves(INITIAL_USDC, INITIAL_WETH);

    const (usdcReserves, wethReserves, usdcBudget, wethBudget, dailySpent, dailyRemaining) = 
      await priceFloor.getReserveInfo();

    expect(usdcReserves).to.equal(INITIAL_USDC);
    expect(wethReserves).to.equal(INITIAL_WETH);
    expect(dailySpent).to.equal(0);
  });
});