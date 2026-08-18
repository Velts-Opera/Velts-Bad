from __future__ import annotations

import os
from collections.abc import Iterable


def normalize_identity(value: str) -> str:
    return value.strip().casefold()


def parse_allowed_identities(raw: str | None = None) -> frozenset[str]:
    source = raw if raw is not None else os.getenv("VELTS_BAD_ALLOWED_IDENTITIES", "")
    return frozenset(
        normalized
        for item in source.split(",")
        if (normalized := normalize_identity(item))
    )


def is_allowed_identity(
    identity: str | None,
    allowed: Iterable[str] | None = None,
) -> bool:
    if not identity:
        return False

    normalized_identity = normalize_identity(identity)
    normalized_allowed = (
        parse_allowed_identities()
        if allowed is None
        else frozenset(normalize_identity(item) for item in allowed if item.strip())
    )
    return normalized_identity in normalized_allowed
