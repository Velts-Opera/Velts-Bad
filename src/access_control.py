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


def identities_match(left: str | None, right: str | None) -> bool:
    if not left or not right:
        return False
    return normalize_identity(left) == normalize_identity(right)


def should_accept_participant(
    identity: str | None,
    *,
    linked_identity: str | None = None,
    allowed: Iterable[str] | None = None,
) -> bool:
    """Enforce one authorized remote participant per private room.

    Before a participant is linked, the first allowlisted identity may be selected.
    After selection, only that exact identity remains authorized in the room. This
    prevents a second allowlisted contact from joining another person's session.
    """
    if not is_allowed_identity(identity, allowed):
        return False
    if linked_identity is None:
        return True
    return identities_match(identity, linked_identity)
