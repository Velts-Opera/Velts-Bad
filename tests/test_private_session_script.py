from pathlib import Path

SCRIPT_PATH = Path("scripts/open-private-session.ps1")


def script_text() -> str:
    return SCRIPT_PATH.read_text(encoding="utf-8")


def test_private_session_token_is_least_privilege():
    text = script_text()

    assert "--join" in text
    assert "--allow-source microphone" in text
    assert '$grantJson = \'{"canPublishData":false}\'' in text
    assert "--grant $grant" in text
    assert "--allow-update-metadata" not in text
    assert "--admin" not in text
    assert "--create" not in text
    assert "--egress" not in text
    assert "--ingress" not in text


def test_private_session_windows_powershell_preserves_grant_json_quotes():
    text = script_text()

    assert "function ConvertTo-NativeJsonArgument" in text
    assert "$PSVersionTable.PSEdition -eq 'Desktop'" in text
    assert "$Json.Replace('\"', '\\\"')" in text
    assert "$grant = ConvertTo-NativeJsonArgument $grantJson" in text


def test_private_session_is_bound_to_velts_bad_and_unique_room():
    text = script_text()

    assert "$agentName = 'velts-bad'" in text
    assert '"velts-bad-$([guid]::NewGuid()' in text
    assert "--agent $agentName" in text


def test_private_session_rejects_ambiguous_identity_syntax():
    text = script_text()

    assert "^[a-z0-9][a-z0-9._@-]{0,63}$" in text
    assert "$allowed -notcontains $normalizedIdentity" in text


def test_private_session_recovers_legacy_concatenated_allowlist():
    text = script_text()

    assert "function Get-AllowedIdentitiesRaw" in text
    assert "$joinedMarker = 'VELTS_BAD_LLM_MODEL='" in text
    assert "$raw.IndexOf($joinedMarker" in text
    assert "$raw.Substring(0, $joinedIndex).Trim()" in text
    assert "$allowedRaw = Get-AllowedIdentitiesRaw $envValues" in text


def test_private_session_uses_agents_playground_instead_of_meet():
    text = script_text()

    assert "$playgroundUrl = 'https://agents-playground.livekit.io/'" in text
    assert "--token-only" in text
    assert "Set-Clipboard -Value $token" in text
    assert "Start-Process $playgroundUrl" in text
    assert "--open meet" not in text
    assert "meet.livekit.io" not in text


def test_private_session_never_prints_jwt():
    text = script_text()

    assert "Token: copiado para a área de transferência" in text
    assert "Write-Host $token" not in text
    assert "Write-Output $token" not in text
    assert "Write-Host $tokenOutput" not in text
    assert "Write-Output $tokenOutput" not in text


def test_private_session_validates_token_shape_before_clipboard():
    text = script_text()

    assert "^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$" in text
    assert "$tokenCandidates.Count -ne 1" in text
    assert "Set-Clipboard -Value $token" in text
