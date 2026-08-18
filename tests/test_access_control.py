from access_control import is_allowed_identity, parse_allowed_identities


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
