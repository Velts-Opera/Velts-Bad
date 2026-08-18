from pathlib import Path

SCRIPT_PATH = Path("scripts/open-private-session.ps1")


def script_text() -> str:
    return SCRIPT_PATH.read_text(encoding="utf-8")


def test_private_session_token_is_least_privilege():
    text = script_text()

    assert "--join" in text
    assert "--allow-source microphone" in text
    assert '"canPublish":true' in text
    assert '"canSubscribe":true' in text
    assert '"canPublishData":false' in text
    assert '"canUpdateOwnMetadata":false' in text
    assert "--admin" not in text
    assert "--create" not in text
    assert "--egress" not in text
    assert "--ingress" not in text


def test_private_session_is_bound_to_velts_bad_and_unique_room():
    text = script_text()

    assert "$agentName = 'velts-bad'" in text
    assert '"velts-bad-$([guid]::NewGuid()' in text
    assert "--agent $agentName" in text


def test_private_session_rejects_ambiguous_identity_syntax():
    text = script_text()

    assert "^[a-z0-9][a-z0-9._@-]{0,63}$" in text
    assert "$allowed -notcontains $normalizedIdentity" in text


def test_private_session_does_not_request_token_output_mode():
    text = script_text()

    # The CLI may produce the generated token on stdout while opening Meet. The
    # helper pipes stdout to Out-Null and never requests token-only/json output.
    assert "| Out-Null" in text
    assert "--token-only" not in text
    assert "--json" not in text
