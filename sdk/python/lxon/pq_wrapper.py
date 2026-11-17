"""PQ Wrapper client — wrap BTC/ETH into quantum-safe assets."""
from __future__ import annotations
from typing import Optional
from eth_account import Account
from .client import LxonClient
from .types import Address, WrappedAsset


class WrapResult:
    def __init__(self, tx_hash: str, ref: str, amount: int, to: Address) -> None:
        self.tx_hash = tx_hash
        self.ref = ref
        self.amount = amount
        self.to = to


class PQWrapperClient:
    """
    Wrap BTC/ETH/USDC into quantum-safe LXON assets.

    Example:
        wrapper = PQWrapperClient(lxon, wrapper_address="0x...")
        result = wrapper.wrap_erc20(
            private_key="0x...",
            amount=1_000_000,
            ref="deposit-2026-01-15",
        )
    """

    def __init__(self, lxon: LxonClient, wrapper_address: Address) -> None:
        self.lxon = lxon
        self.wrapper = wrapper_address

    def wrap_erc20(self, private_key: str, amount: int, ref: str) -> WrapResult:
        """Wrap an ERC20 underlying (requires approve first)."""
        acct = Account.from_key(private_key)

        sel = bytes.fromhex("b8d1d5f4")  # selector for wrapERC20
        ref_b = bytes.fromhex(ref.replace("0x", "").zfill(64))[:32]
        data = sel + amount.to_bytes(32, "big") + ref_b

        tx = {
            "to": self.wrapper,
            "data": "0x" + data.hex(),
            "gas": 200_000,
            "gasPrice": self.lxon._call("eth_gasPrice"),
            "nonce": int(self.lxon._call("eth_getTransactionCount", [acct.address, "pending"]), 16),
            "chainId": self.lxon.get_chain_id(),
        }
        signed = acct.sign_transaction(tx)
        tx_hash = self.lxon._call("eth_sendRawTransaction", ["0x" + signed.raw_transaction.hex()])
        return WrapResult(tx_hash=tx_hash, ref=ref, amount=amount, to=acct.address)

    def unwrap(self, private_key: str, amount: int, ref: str) -> WrapResult:
        acct = Account.from_key(private_key)
        sel = bytes.fromhex("5d3a3d4f")  # selector for unwrap
        ref_b = bytes.fromhex(ref.replace("0x", "").zfill(64))[:32]
        data = sel + amount.to_bytes(32, "big") + ref_b

        tx = {
            "to": self.wrapper,
            "data": "0x" + data.hex(),
            "gas": 200_000,
            "gasPrice": self.lxon._call("eth_gasPrice"),
            "nonce": int(self.lxon._call("eth_getTransactionCount", [acct.address, "pending"]), 16),
            "chainId": self.lxon.get_chain_id(),
        }
        signed = acct.sign_transaction(tx)
        tx_hash = self.lxon._call("eth_sendRawTransaction", ["0x" + signed.raw_transaction.hex()])
        return WrapResult(tx_hash=tx_hash, ref=ref, amount=amount, to=acct.address)

    def get_asset(self, address: Address) -> WrappedAsset:
        return WrappedAsset(**self.lxon.get_wrapped_asset(address))