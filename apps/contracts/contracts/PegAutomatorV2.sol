// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IWLXON {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface ILxswapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface ILxswapPair {
    function getReserves() external view returns (uint112, uint112, uint32);
}

interface IPegStabilityModule {
    function deposit() external payable;
}

contract PegAutomatorV2 is Pausable, Ownable, ReentrancyGuard {
    IWLXON public immutable wlxon;
    IERC20 public immutable usdc;
    ILxswapRouter public immutable router;
    ILxswapPair public immutable pair;
    IPegStabilityModule public immutable psm;
    address public immutable lxonToken;

    uint256 public totalWlxonReserves;
    uint256 public constant PRICE_PRECISION = 1e18;

    constructor(
        address _wlxon, address _usdc, address _router, address _pair, address _psm, address _lxon, address owner_
    ) Ownable(owner_) {
        wlxon  = IWLXON(_wlxon);
        usdc   = IERC20(_usdc);
        router = ILxswapRouter(_router);
        pair   = ILxswapPair(_pair);
        psm    = IPegStabilityModule(_psm);
        lxonToken = _lxon;
    }

    receive() external payable {
        wlxon.deposit{value: msg.value}();
        totalWlxonReserves += msg.value;
    }

    function fund() external payable {
        require(msg.value > 0, "AUTO: ZERO_ETH");
        wlxon.deposit{value: msg.value}();
        totalWlxonReserves += msg.value;
    }

    function buyLxonWithUSDC(uint256 usdcAmount) external returns (uint256) {
        require(msg.sender == owner() || msg.sender == keeper(), "AUTO: FORBIDDEN");
        require(usdc.balanceOf(address(this)) >= usdcAmount, "AUTO: INSUFFICIENT_USDC");

        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = lxonToken;
        IERC20(address(usdc)).approve(address(router), usdcAmount);
        uint256[] memory amounts = router.swapExactTokensForTokens(
            usdcAmount, 0, path, address(this), block.timestamp + 300
        );
        return amounts[1];
    }

    function withdrawETH(uint256 amount, address to) external onlyOwner nonReentrant {
        require(totalWlxonReserves >= amount, "AUTO: INSUFFICIENT_WLXON");
        totalWlxonReserves -= amount;
        wlxon.withdraw(amount);
        (bool ok,) = to.call{value: amount}("");
        require(ok, "AUTO: ETH_SEND_FAILED");
    }

    function defendPeg() public {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        if (reserve0 == 0 || reserve1 == 0) return;

        uint256 price = (uint256(reserve1) * PRICE_PRECISION) / uint256(reserve0);

        if (price < 0.95e18) {
            uint256 usdcBalance = usdc.balanceOf(address(this));
            if (usdcBalance > 0) {
                address[] memory path = new address[](2);
                path[0] = address(usdc);
                path[1] = lxonToken;
                IERC20(address(usdc)).approve(address(router), usdcBalance);
                router.swapExactTokensForTokens(usdcBalance, 0, path, address(this), block.timestamp + 300);
            }
        } else if (price > 1.05e18) {
            uint256 lxonBal = IERC20(lxonToken).balanceOf(address(this));
            if (lxonBal > 0) {
                address[] memory path = new address[](2);
                path[0] = lxonToken;
                path[1] = address(usdc);
                IERC20(address(lxonToken)).approve(address(router), lxonBal);
                router.swapExactTokensForTokens(lxonBal, 0, path, address(this), block.timestamp + 300);
            }
        }
    }

    function checkUpkeep() public view returns (bool upkeepNeeded, uint256) {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        if (reserve0 == 0 || reserve1 == 0) return (false, 0);
        uint256 price = (uint256(reserve1) * PRICE_PRECISION) / uint256(reserve0);
        upkeepNeeded = (price < 0.95e18 || price > 1.05e18);
        return (upkeepNeeded, 0);
    }

    function performUpkeep() external {
        (bool upkeepNeeded, ) = checkUpkeep();
        if (upkeepNeeded) {
            defendPeg();
        }
    }

    function keeper() internal view returns (address) {
        return address(this);
    }
}
