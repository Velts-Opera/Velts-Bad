from pathlib import Path

SCRIPT_PATH = Path("scripts/open-private-session.ps1")
CLIENT_PATH = Path("scripts/private-session-client.html")
CLIENT_JS_PATH = Path("scripts/private-session-client.js")
EXPECTED_SERVER_URL = "wss://veltsapp-j8mqf7tp.livekit.cloud"


def script_text() -> str:
    return SCRIPT_PATH.read_text(encoding="utf-8")


def client_text() -> str:
    return CLIENT_PATH.read_text(encoding="utf-8")


def client_js_text() -> str:
    return CLIENT_JS_PATH.read_text(encoding="utf-8")


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


def test_private_session_is_pinned_to_production_livekit_endpoint():
    text = script_text()

    assert "function Get-LiveKitUrl" in text
    assert f"$expected = '{EXPECTED_SERVER_URL}'" in text
    assert "$fromEnv -ne $expected" in text
    assert "LIVEKIT_URL does not match the Velts-Bad production LiveKit project" in text
    assert "return $expected" in text


def test_private_session_normalizes_wrapping_quotes_before_endpoint_check():
    text = script_text()

    assert "$raw = ([string]$Values['LIVEKIT_URL']).Trim()" in text
    assert "$isDoubleQuoted" in text
    assert "$isSingleQuoted" in text
    assert "$raw = $raw.Substring(1, $raw.Length - 2).Trim()" in text
    assert "$fromEnv = $raw.TrimEnd('/')" in text


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


def test_local_client_csp_is_narrow_and_does_not_send_referrer():
    html = client_text()

    assert "script-src 'self' https://cdn.jsdelivr.net" in html
    assert f"connect-src {EXPECTED_SERVER_URL} https://veltsapp-j8mqf7tp.livekit.cloud" in html
    assert "connect-src wss: ws: https:" not in html
    assert '<meta name="referrer" content="no-referrer">' in html
    assert '<script src="/private-session-client.js"></script>' in html
    assert "<script>" not in html


def test_local_client_populates_server_and_room_from_query_params():
    js = client_js_text()

    assert "new URLSearchParams(window.location.search)" in js
    assert "serverInput.value = params.get('server') || ''" in js
    assert "roomInput.value = params.get('room') || ''" in js


def test_local_client_rejects_redirected_server_or_invalid_room():
    js = client_js_text()

    assert f"const EXPECTED_SERVER_URL = '{EXPECTED_SERVER_URL}'" in js
    assert "const PRIVATE_ROOM_PATTERN = /^velts-bad-[0-9a-f]{16}$/" in js
    assert "serverUrl !== EXPECTED_SERVER_URL" in js
    assert "!PRIVATE_ROOM_PATTERN.test(roomName)" in js


def test_local_client_reads_token_from_clipboard_on_connect_with_manual_fallback():
    html = client_text()
    js = client_js_text()

    assert "navigator.clipboard.readText()" in js
    assert "tokenFallback.hidden = false" in js
    assert 'id="tokenFallback" hidden' in html
    assert "navigator.clipboard.writeText('[cleared]')" in js


def test_local_client_is_microphone_only_and_subscribes_audio():
    html = client_text()
    js = client_js_text()

    assert "livekit-client@2.21.0" in html
    assert "room.localParticipant.setMicrophoneEnabled(true)" in js
    assert "setCameraEnabled" not in js
    assert "enableCameraAndMicrophone" not in js
    assert "RoomEvent.TrackSubscribed" in js
    assert "track.kind !== Track.Kind.Audio" in js
    assert "track.attach()" in js
    assert "Fale com a Stella" in js


def test_local_client_does_not_persist_token_in_url_or_storage():
    js = client_js_text()

    assert "params.get('token')" not in js
    assert "localStorage" not in js
    assert "sessionStorage" not in js
    assert "tokenInput.value = ''" in js
