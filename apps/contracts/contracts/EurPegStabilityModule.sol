// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ILXON {
    function mint(address to, uint256 usdCents, bytes32 depositRef) external;
    function burn(address from, uint256 amount) external;
}

contract EurPegStabilityModule is Pausable, Ownable {
    IERC20 public immutable eurc;     // EURC (6 decimals)
    ILXON  public immutable lxon;     // LXON (6 decimals)

    uint256 public constant PEG_1E6 = 1e6;  // €1.00 target (6 decimals)
    uint256 public mintFeeBps = 10;
    uint256 public redeemFeeBps = 10;
    uint256 public totalEurcReserves;
    uint256 public totalLxonReserves;

    event Minted(address indexed user, uint256 eurcIn, uint256 lxonOut, uint256 fee);
    event Redeemed(address indexed user, uint256 lxonIn, uint256 eurcOut, uint256 fee);

    constructor(address _eurc, address _lxon, address owner_)
        Ownable(owner_)
    {
        eurc = IERC20(_eurc);
        lxon = ILXON(_lxon);
    }

    function mint(uint256 eurcAmount) external returns (uint256 lxonOut) {
        require(eurcAmount > 0, "PSM: ZERO_AMOUNT");
        uint256 fee = (eurcAmount * mintFeeBps) / 10_000;
        uint256 netEurc = eurcAmount - fee;

        SafeERC20.safeTransferFrom(IERC20(eurc), msg.sender, address(this), eurcAmount);

        // Both EURC and LXON have 6 decimals: 1:1 conversion
        lxonOut = netEurc;
        uint256 usdCents = lxonOut / 1e4;  // units → usdCents for LXON.mint

        lxon.mint(msg.sender, usdCents, bytes32(0));
        totalEurcReserves += netEurc;
        totalLxonReserves += lxonOut;

        emit Minted(msg.sender, eurcAmount, lxonOut, fee);
    }

    function redeem(uint256 lxonAmount) external returns (uint256 eurcOut) {
        require(lxonAmount > 0, "PSM: ZERO_AMOUNT");
        uint256 fee = (lxonAmount * redeemFeeBps) / 10_000;
        eurcOut = lxonAmount - fee;

        ILXON(address(lxon)).burn(msg.sender, lxonAmount);
        SafeERC20.safeTransfer(IERC20(eurc), msg.sender, eurcOut);

        totalLxonReserves -= lxonAmount;
        totalEurcReserves -= eurcOut;

        emit Redeemed(msg.sender, lxonAmount, eurcOut, fee);
    }

    function setMintFeeBps(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 1000, "PSM: FEE_TOO_HIGH");
        mintFeeBps = _feeBps;
    }

    function setRedeemFeeBps(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 1000, "PSM: FEE_TOO_HIGH");
        redeemFeeBps = _feeBps;
    }

    receive() external payable {}
}
