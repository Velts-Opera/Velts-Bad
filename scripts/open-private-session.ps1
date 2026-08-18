param(
    [Parameter(Mandatory = $true)]
    [string]$Identity,

    [ValidateRange(5, 30)]
    [int]$ValidForMinutes = 15
)

$ErrorActionPreference = 'Stop'

function Read-DotEnv([string]$Path) {
    if (-not (Test-Path $Path)) {
        throw "File $Path not found."
    }

    $values = @{}
    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#') -or -not $trimmed.Contains('=')) {
            continue
        }

        $parts = $trimmed.Split('=', 2)
        $values[$parts[0].Trim()] = $parts[1].Trim()
    }
    return $values
}

function Get-AllowedIdentitiesRaw([hashtable]$Values) {
    $raw = [string]$Values['VELTS_BAD_ALLOWED_IDENTITIES']
    if (-not $raw) {
        return ''
    }

    # Recover from an old PowerShell Add-Content edge case where the next env
    # assignment was appended to the allowlist because the file lacked a final
    # newline, e.g. "veltsVELTS_BAD_LLM_MODEL=...".
    $joinedMarker = 'VELTS_BAD_LLM_MODEL='
    $joinedIndex = $raw.IndexOf($joinedMarker, [System.StringComparison]::Ordinal)
    if ($joinedIndex -ge 0) {
        $raw = $raw.Substring(0, $joinedIndex).Trim()
    }

    return $raw
}

function ConvertTo-NativeJsonArgument([string]$Json) {
    # Windows PowerShell 5.x strips unescaped inner double quotes when passing
    # string arguments to native executables. PowerShell 7+ does not.
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        return $Json.Replace('"', '\"')
    }

    return $Json
}

function Get-LiveKitUrl([hashtable]$Values) {
    $fromEnv = ([string]$Values['LIVEKIT_URL']).Trim()
    if ($fromEnv -match '^wss://[A-Za-z0-9.-]+(?::[0-9]+)?(?:/.*)?$') {
        return $fromEnv
    }

    # This repository and deploy helper are intentionally bound to the VeltsApp
    # LiveKit Cloud project. The project URL is public connection metadata, not
    # a credential, so a fixed fallback is safer than parsing CLI table output.
    return 'wss://veltsapp-j8mqf7tp.livekit.cloud'
}

if (-not (Get-Command lk -ErrorAction SilentlyContinue)) {
    throw 'LiveKit CLI (lk) not found.'
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git not found.'
}

if (-not (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
    throw 'Set-Clipboard is not available in this PowerShell.'
}

$repoRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) {
    throw 'Run this script from inside the Velts-Bad Git repository.'
}
Set-Location $repoRoot

$envValues = Read-DotEnv '.env.local'
$liveKitUrl = Get-LiveKitUrl $envValues

$allowedRaw = Get-AllowedIdentitiesRaw $envValues
if (-not $allowedRaw) {
    throw 'VELTS_BAD_ALLOWED_IDENTITIES is missing or empty in .env.local.'
}

$allowed = @(
    $allowedRaw.Split(',') |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ }
)

$normalizedIdentity = $Identity.Trim().ToLowerInvariant()
if (-not $normalizedIdentity) {
    throw 'Identity cannot be empty.'
}

# Keep CLI values unambiguous and predictable.
if ($normalizedIdentity -notmatch '^[a-z0-9][a-z0-9._@-]{0,63}$') {
    throw 'Invalid identity. Use 1-64 chars: a-z, 0-9, dot, underscore, @ or hyphen; first char must be alphanumeric.'
}

if ($allowed -notcontains $normalizedIdentity) {
    throw "Identity '$Identity' is not in the local Velts-Bad allowlist."
}

$room = "velts-bad-$([guid]::NewGuid().ToString('N').Substring(0, 16))"
$ttl = "${ValidForMinutes}m"
$agentName = 'velts-bad'
$playgroundUrl = 'https://agents-playground.livekit.io/'

# Only microphone publication is allowed. canPublishData must be explicitly
# false because LiveKit otherwise derives it from canPublish.
$grantJson = '{"canPublishData":false}'
$grant = ConvertTo-NativeJsonArgument $grantJson

Write-Host "Preparing private session [$room] for identity [$normalizedIdentity]..."
Write-Host "Temporary token TTL: $ttl. The token value will not be printed."

$tokenOutput = & lk token create `
    --identity $normalizedIdentity `
    --room $room `
    --agent $agentName `
    --join `
    --allow-source microphone `
    --grant $grant `
    --valid-for $ttl `
    --token-only

if ($LASTEXITCODE -ne 0) {
    throw "LiveKit CLI exited with code $LASTEXITCODE while creating the private token."
}

$tokenCandidates = @(
    $tokenOutput |
        ForEach-Object { ([string]$_).Trim() } |
        Where-Object { $_ -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' }
)

if ($tokenCandidates.Count -ne 1) {
    throw 'LiveKit CLI did not return exactly one valid JWT. Token was not copied.'
}

$token = $tokenCandidates[0]
Set-Clipboard -Value $token
Start-Process $playgroundUrl

Write-Host 'Agents Playground opened.'
Write-Host "LiveKit URL: $liveKitUrl"
Write-Host "Room: $room"
Write-Host 'Token: copied to clipboard. Paste it into the Playground token field.'
Write-Host 'Keep CAMERA OFF and enable MICROPHONE only.'
Write-Host "After connecting, clear the clipboard with: Set-Clipboard -Value ''"
