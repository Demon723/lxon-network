// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ILXON {
    function mint(address to, uint256 usdCents, bytes32 depositRef) external;
    function burn(address from, uint256 amount) external;
}

interface IWLXON {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract PegStabilityModule is Pausable, Ownable, ReentrancyGuard {
    IWLXON public immutable wlxon;
    IERC20 public immutable usdc;
    address public immutable lxonToken;
    address public automator;

    uint256 public mintFeeBps   = 10;
    uint256 public redeemFeeBps = 10;
    uint256 public totalUsdcReserves;
    uint256 public totalWlxonReserves;

    event EthMinted(address indexed user, uint256 ethIn, uint256 lxonOut, uint256 fee);
    event EthRedeemed(address indexed user, uint256 lxonIn, uint256 ethOut, uint256 fee);
    event AutomatorUpdated(address indexed automator);

    constructor(address _wlxon, address _usdc, address _lxon, address _automator, address owner_)
        Ownable(owner_)
    {
        wlxon = IWLXON(_wlxon);
        usdc  = IERC20(_usdc);
        lxonToken = _lxon;
        automator = _automator;
    }

    function setAutomator(address _automator) external onlyOwner {
        automator = _automator;
        emit AutomatorUpdated(_automator);
    }

    function mintWithETH() external payable returns (uint256 lxonOut) {
        require(msg.value > 0, "PSM: ZERO_ETH");
        uint256 fee = (msg.value * mintFeeBps) / 10_000;
        lxonOut = msg.value - fee;

        wlxon.deposit{value: msg.value}();
        totalWlxonReserves += msg.value;

        ILXON(address(lxonToken)).mint(msg.sender, lxonOut / 1e4, bytes32(0));

        emit EthMinted(msg.sender, msg.value, lxonOut, fee);
    }

    function redeemToETH(uint256 lxonAmount) external nonReentrant returns (uint256 ethOut) {
        require(lxonAmount > 0, "PSM: ZERO_AMOUNT");
        uint256 fee = (lxonAmount * redeemFeeBps) / 10_000;
        ethOut = lxonAmount - fee;

        require(totalWlxonReserves >= ethOut, "PSM: INSUFFICIENT_RESERVES");

        SafeERC20.safeTransferFrom(IERC20(lxonToken), msg.sender, address(this), lxonAmount);
        ILXON(address(lxonToken)).burn(address(this), lxonAmount);

        totalWlxonReserves -= ethOut;
        wlxon.withdraw(ethOut);
        (bool ok,) = msg.sender.call{value: ethOut}("");
        require(ok, "PSM: ETH_SEND_FAILED");

        emit EthRedeemed(msg.sender, lxonAmount, ethOut, fee);
    }

    receive() external payable {
        wlxon.deposit{value: msg.value}();
        totalWlxonReserves += msg.value;
    }
}
