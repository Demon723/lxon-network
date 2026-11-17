"""Shared types for the LXON Python SDK."""
from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, Field

Address = str  # 0x-prefixed hex


class WrappedAsset(BaseModel):
    name: str
    symbol: str
    address: Address
    underlying: Address
    asset_class: str = Field(alias="assetClass")
    total_minted: int = Field(alias="totalMinted")
    total_redeemed: int = Field(alias="totalRedeemed")

    class Config:
        populate_by_name = True


class Attestation(BaseModel):
    ref: str
    to: Address
    amount: int
    asset_id: str = Field(alias="assetId")
    custodian: str
    submitted_at: int = Field(alias="submittedAt")

    class Config:
        populate_by_name = True


class Session(BaseModel):
    id: str
    client: Address
    satellite_id: str = Field(alias="satelliteId")
    station_id: str = Field(alias="stationId")
    bytes_used: int = Field(alias="bytesUsed")
    opened_at_ms: int = Field(alias="openedAtMs")

    class Config:
        populate_by_name = True


class Pass(BaseModel):
    satellite_id: str = Field(alias="satelliteId")
    start_ms: int = Field(alias="startMs")
    end_ms: int = Field(alias="endMs")
    max_elevation_deg: float = Field(alias="maxElevationDeg")

    class Config:
        populate_by_name = True