from pathlib import Path

SCRIPT_PATH = Path("scripts/open-private-session.ps1")
CLIENT_PATH = Path("scripts/private-session-client.html")


def script_text() -> str:
    return SCRIPT_PATH.read_text(encoding="utf-8")


def client_text() -> str:
    return CLIENT_PATH.read_text(encoding="utf-8")


def test_private_session_script_is_ascii_safe_for_windows_powershell_5():
    SCRIPT_PATH.read_bytes().decode("ascii")


def test_private_session_token_is_least_privilege():
    text = script_text()

    assert "--join" in text
    assert "--allow-source microphone" in text
    assert '$grantJson = \'{"canPublishData":false}\'' in text
    assert "--grant $grant" in text
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


def test_private_session_uses_local_client_not_removed_hosted_playground_or_meet():
    text = script_text()

    assert "private-session-client.html" in text
    assert "http.server" in text
    assert "--bind', '127.0.0.1" in text
    assert "--token-only" in text
    assert "Set-Clipboard -Value $token" in text
    assert "agents-playground.livekit.io" not in text
    assert "meet.livekit.io" not in text
    assert "--open meet" not in text


def test_local_server_uses_working_directory_instead_of_unquoted_directory_argument():
    text = script_text()

    assert "-WorkingDirectory $clientDir" in text
    assert "'--directory'" not in text
    assert "$serverArgs = @('-m', 'http.server', [string]$port, '--bind', '127.0.0.1')" in text


def test_local_server_verifies_python_launcher_is_functional():
    text = script_text()

    assert "function Test-PythonCommand" in text
    assert "& $CommandPath --version" in text
    assert "Test-PythonCommand $command.Source" in text
    assert "No functional Python launcher found" in text


def test_private_session_never_prints_jwt_or_puts_it_in_url():
    text = script_text()

    assert "Write-Host $token" not in text
    assert "Write-Output $token" not in text
    assert "Write-Host $tokenOutput" not in text
    assert "Write-Output $tokenOutput" not in text
    assert "$clientUrl" in text
    assert "token=$token" not in text


def test_private_session_validates_token_shape_before_clipboard():
    text = script_text()

    assert "^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$" in text
    assert "$tokenCandidates.Count -ne 1" in text
    assert "Set-Clipboard -Value $token" in text


def test_local_client_is_microphone_only_and_subscribes_audio():
    text = client_text()

    assert "livekit-client@2.21.0" in text
    assert "room.localParticipant.setMicrophoneEnabled(true)" in text
    assert "setCameraEnabled" not in text
    assert "enableCameraAndMicrophone" not in text
    assert "RoomEvent.TrackSubscribed" in text
    assert "track.kind !== Track.Kind.Audio" in text
    assert "track.attach()" in text


def test_local_client_does_not_persist_token_in_url_or_storage():
    text = client_text()

    assert "params.get('token')" not in text
    assert "localStorage" not in text
    assert "sessionStorage" not in text
    assert "tokenInput.value = ''" in text
    assert "navigator.clipboard.writeText('[cleared]')" in text
