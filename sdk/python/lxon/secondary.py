"""Secondary PQ signature helpers."""
from __future__ import annotations
import hashlib
from dataclasses import dataclass
from typing import Literal

SecondaryScheme = Literal['MAYO-1', 'MAYO-2', 'MAYO-3', 'MAYO-5']


@dataclass
class SecondaryCommitment:
    commitment: str
    scheme: SecondaryScheme


def compute_commitment(message: bytes, public_key: bytes, signature: bytes) -> str:
    h = hashlib.sha256()
    h.update(message)
    h.update(public_key)
    h.update(signature)
    return "0x" + h.hexdigest()


MAYO_PARAMS = {
    "MAYO-1": {"sig": 454, "pk": 1420},
    "MAYO-2": {"sig": 216, "pk": 4368},
    "MAYO-3": {"sig": 681, "pk": 2986},
    "MAYO-5": {"sig": 964, "pk": 5554},
}
