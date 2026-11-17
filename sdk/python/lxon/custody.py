"""Custodian integration client."""
from __future__ import annotations
import httpx
from typing import Optional
from .types import Address, Attestation


class CustodyClient:
    """Submit custodian attestations to the LXON vault."""

    def __init__(self, rpc_url: str = "http://localhost:8545") -> None:
        self.rpc_url = rpc_url
        self._client = httpx.Client(timeout=30.0)
        self._id = 0

    def _call(self, method: str, params: list) -> dict:
        self._id += 1
        payload = {"jsonrpc": "2.0", "id": self._id, "method": method, "params": params}
        r = self._client.post(self.rpc_url, json=payload)
        r.raise_for_status()
        return r.json()

    def submit_attestation(
        self,
        ref: str,
        asset_id: str,
        custodian: str,
        to: Address,
        amount: int,
        proof: str,
    ) -> dict:
        return self._call("lxon_submitAttestation", [
            ref, asset_id, custodian, to, amount, proof,
        ])

    def get_attestation(self, ref: str) -> Optional[Attestation]:
        result = self._call("lxon_getAttestation", [ref])
        if not result.get("result"):
            return None
        return Attestation(**result["result"])

    def close(self) -> None:
        self._client.close()