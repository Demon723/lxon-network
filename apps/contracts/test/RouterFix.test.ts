import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";
import { WETH9, LXON, Pair, Router } from "../typechain-types";

describe("Router Liquidity Fix", function () {
  let weth: WETH9;
  let lxon: LXON;
  let pair: Pair;
  let router: Router;
  let owner: Signer;
  let user: Signer;
  let ownerAddress: string;
  let userAddress: string;

  const INITIAL_LXON = ethers.parseEther("1000");
  const INITIAL_WETH = ethers.parseEther("1000");

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();
    ownerAddress = await owner.getAddress();
    userAddress = await user.getAddress();

    // Deploy WETH
    const WETH = await ethers.getContractFactory("WETH9");
    weth = await WETH.deploy();

    // Deploy LXON
    const LXON = await ethers.getContractFactory("LXON");
    lxon = await LXON.deploy(ownerAddress);

    // Deploy Pair
    const Pair = await ethers.getContractFactory("Pair");
    pair = await Pair.deploy(await weth.getAddress(), await lxon.getAddress());

    // Deploy Router
    const Router = await ethers.getContractFactory("Router");
    router = await Router.deploy(
      await weth.getAddress(),
      await lxon.getAddress(),
      await pair.getAddress()
    );

    // Setup LXON roles
    const MINT_ROLE = await lxon.MINT_ROLE();
    await lxon.grantRole(MINT_ROLE, ownerAddress);

    // Mint LXON to owner
    await lxon.mint(ownerAddress, INITIAL_LXON, ethers.ZeroHash);
  });

  it("should add initial liquidity correctly", async function () {
    // Deposit ETH to get WETH
    await weth.deposit({ value: INITIAL_WETH });

    // Approve router
    await weth.approve(await router.getAddress(), INITIAL_WETH);
    await lxon.approve(await router.getAddress(), INITIAL_LXON);

    // Add initial liquidity
    const tx = await router.addLiquidity(
      INITIAL_LXON,
      INITIAL_WETH,
      INITIAL_LXON,
      INITIAL_WETH,
      ownerAddress,
      Math.floor(Date.now() / 1000) + 3600
    );

    const receipt = await tx.wait();
    console.log("Gas used:", receipt?.gasUsed.toString());

    // Check reserves
    const [reserve0, reserve1] = await pair.getReserves();
    expect(reserve0).to.equal(INITIAL_LXON);
    expect(reserve1).to.equal(INITIAL_WETH);

    // Check LP tokens
    const lpBalance = await pair.balanceOf(ownerAddress);
    expect(lpBalance).to.be.gt(0);

    console.log("LP tokens minted:", ethers.formatEther(lpBalance));
  });

  it("should fail without token approvals", async function () {
    // Deposit ETH to get WETH
    await weth.deposit({ value: INITIAL_WETH });

    // Don't approve router
    await expect(
      router.addLiquidity(
        INITIAL_LXON,
        INITIAL_WETH,
        INITIAL_LXON,
        INITIAL_WETH,
        ownerAddress,
        Math.floor(Date.now() / 1000) + 3600
      )
    ).to.be.reverted;
  });

  it("should allow second liquidity provider", async function () {
    // First liquidity
    await weth.deposit({ value: INITIAL_WETH });
    await weth.approve(await router.getAddress(), INITIAL_WETH);
    await lxon.approve(await router.getAddress(), INITIAL_LXON);
    await router.addLiquidity(
      INITIAL_LXON,
      INITIAL_WETH,
      INITIAL_LXON,
      INITIAL_WETH,
      ownerAddress,
      Math.floor(Date.now() / 1000) + 3600
    );

    // Second liquidity
    const secondLXON = ethers.parseEther("500");
    const secondWETH = ethers.parseEther("500");

    await lxon.mint(userAddress, secondLXON, ethers.ZeroHash);
    
    await weth.connect(user).deposit({ value: secondWETH });
    await weth.connect(user).approve(await router.getAddress(), secondWETH);
    await lxon.connect(user).approve(await router.getAddress(), secondLXON);

    await router.connect(user).addLiquidity(
      secondLXON,
      secondWETH,
      secondLXON,
      secondWETH,
      userAddress,
      Math.floor(Date.now() / 1000) + 3600
    );

    const userLpBalance = await pair.balanceOf(userAddress);
    expect(userLpBalance).to.be.gt(0);
    console.log("Second provider LP tokens:", ethers.formatEther(userLpBalance));
  });
});