"""Satellite gateway client."""
from __future__ import annotations
import httpx
from base64 import b64encode
from typing import Optional
from .types import Address, Session, Pass


class SatelliteClient:
    """Client for the LXON satellite gateway."""

    def __init__(self, gateway_url: str = "http://localhost:4100", token: Optional[str] = None) -> None:
        self.gateway_url = gateway_url.rstrip("/")
        self.token = token
        self._client = httpx.Client(timeout=30.0)

    def _headers(self) -> dict:
        h = {"content-type": "application/json"}
        if self.token:
            h["authorization"] = f"Bearer {self.token}"
        return h

    def health(self) -> dict:
        return self._client.get(f"{self.gateway_url}/api/v1/satellite/health").json()

    def uplink(self, satellite_id: str, data: bytes, priority: str = "normal") -> dict:
        r = self._client.post(
            f"{self.gateway_url}/api/v1/satellite/uplink",
            headers=self._headers(),
            json={
                "satelliteId": satellite_id,
                "dataBase64": b64encode(data).decode(),
                "priority": priority,
            },
        )
        r.raise_for_status()
        return r.json()

    def open_session(self, client: Address, satellite_id: str, station_id: str, deposit_wei: int, bytes_allowance: int) -> Session:
        r = self._client.post(
            f"{self.gateway_url}/api/v1/satellite/sessions",
            headers=self._headers(),
            json={
                "client": client,
                "satelliteId": satellite_id,
                "stationId": station_id,
                "depositWei": str(deposit_wei),
                "bytesAllowance": str(bytes_allowance),
            },
        )
        r.raise_for_status()
        return Session(**r.json())

    def get_passes(self, station_id: str, horizon_s: int = 3600) -> list[Pass]:
        r = self._client.get(
            f"{self.gateway_url}/api/v1/satellite/passes/{station_id}",
            params={"horizon": horizon_s},
            headers=self._headers(),
        )
        r.raise_for_status()
        return [Pass(**p) for p in r.json().get("passes", [])]

    def close(self) -> None:
        self._client.close()