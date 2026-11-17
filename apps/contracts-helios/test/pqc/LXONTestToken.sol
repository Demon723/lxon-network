// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IBridgedToken} from "../../src/pqc/LXONPqcBridgeV1.sol";

/// PqcBridgeHarness's token: the minimum surface the copied bridge actually calls.
/// `bridge` is settable rather than immutable because the harness creates the token
/// before the bridge; nothing here is production token code, and the tests that
/// matter (Escrow binding, Mint cap, Release escrow short) only need `bridge()` to
/// answer the truth at the moment setOutbound/setInbound ask.
contract LXONTestToken is ERC20, IBridgedToken {
    address public override bridge;

    constructor() ERC20("LXON Test Token", "LXONT") {}

    function setBridge(address b) external {
        bridge = b;
    }

    /// The harness's stand-in for a minter role: tests mint to themselves, and the
    /// bridge is the only other caller that matters.
    function mint(address to, uint256 amount) external override {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external override {
        _burn(from, amount);
    }

    function totalSupply() public view override(ERC20, IBridgedToken) returns (uint256) {
        return super.totalSupply();
    }
}
