from access_control import (
    identities_match,
    is_allowed_identity,
    parse_allowed_identities,
    should_accept_participant,
)


def test_empty_allowlist_denies_everyone():
    assert parse_allowed_identities("") == frozenset()
    assert not is_allowed_identity("alice", [])


def test_allowed_identity_matches_case_insensitively():
    allowed = parse_allowed_identities(" Velts , Alice ")
    assert is_allowed_identity("velts", allowed)
    assert is_allowed_identity("ALICE", allowed)


def test_unknown_identity_is_denied():
    allowed = parse_allowed_identities("velts,alice")
    assert not is_allowed_identity("bob", allowed)


def test_missing_identity_is_denied():
    assert not is_allowed_identity(None, ["velts"])
    assert not is_allowed_identity("", ["velts"])


def test_first_allowlisted_contact_may_be_selected():
    allowed = parse_allowed_identities("velts,alice")
    assert should_accept_participant("alice", allowed=allowed)


def test_second_allowlisted_contact_cannot_join_existing_private_session():
    allowed = parse_allowed_identities("velts,alice")
    assert not should_accept_participant(
        "alice",
        linked_identity="velts",
        allowed=allowed,
    )


def test_same_linked_identity_remains_authorized_case_insensitively():
    allowed = parse_allowed_identities("velts,alice")
    assert should_accept_participant(
        "VELTS",
        linked_identity="velts",
        allowed=allowed,
    )
    assert identities_match(" VELTS ", "velts")
