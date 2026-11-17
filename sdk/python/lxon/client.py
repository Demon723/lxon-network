"""Main LXON client."""
from __future__ import annotations
import httpx
from typing import Any, Optional

Address = str


class LxonClient:
    """
    High-level client for LXON RPC + gateway.

    Example:
        client = LxonClient(rpc_url="http://localhost:8545")
        block = await client.get_block_number()
    """

    def __init__(
        self,
        rpc_url: str = "http://localhost:8545",
        gateway_url: Optional[str] = None,
        timeout: float = 30.0,
    ) -> None:
        self.rpc_url = rpc_url
        self.gateway_url = gateway_url
        self._client = httpx.Client(timeout=timeout)
        self._id = 0

    def _call(self, method: str, params: list[Any] | None = None) -> Any:
        self._id += 1
        payload = {"jsonrpc": "2.0", "id": self._id, "method": method, "params": params or []}
        r = self._client.post(self.rpc_url, json=payload)
        r.raise_for_status()
        j = r.json()
        if "error" in j and j["error"]:
            raise RuntimeError(f"RPC error: {j['error']}")
        return j["result"]

    def get_block_number(self) -> int:
        return int(self._call("eth_blockNumber"), 16)

    def get_balance(self, address: Address) -> int:
        return int(self._call("eth_getBalance", [address, "latest"]), 16)

    def get_chain_id(self) -> int:
        return int(self._call("eth_chainId"), 16)

    def get_transaction(self, tx_hash: str) -> dict:
        return self._call("eth_getTransactionByHash", [tx_hash])

    def get_wrapped_asset(self, address: Address) -> dict:
        return self._call("lxon_getWrappedAsset", [address])

    def get_wrap_history(self, user: Address, limit: int = 100) -> list[dict]:
        return self._call("lxon_getWrapHistory", [user, limit])

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "LxonClient":
        return self

    def __exit__(self, *args) -> None:
        self.close()