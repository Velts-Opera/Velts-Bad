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

    $joinedMarker = 'VELTS_BAD_LLM_MODEL='
    $joinedIndex = $raw.IndexOf($joinedMarker, [System.StringComparison]::Ordinal)
    if ($joinedIndex -ge 0) {
        $raw = $raw.Substring(0, $joinedIndex).Trim()
    }

    return $raw
}

function ConvertTo-NativeJsonArgument([string]$Json) {
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        return $Json.Replace('"', '\"')
    }

    return $Json
}

function Get-LiveKitUrl([hashtable]$Values) {
    $expected = 'wss://veltsapp-j8mqf7tp.livekit.cloud'
    $raw = ([string]$Values['LIVEKIT_URL']).Trim()

    if (-not $raw) {
        return $expected
    }

    $isDoubleQuoted = $raw.Length -ge 2 -and $raw.StartsWith('"') -and $raw.EndsWith('"')
    $isSingleQuoted = $raw.Length -ge 2 -and $raw.StartsWith("'") -and $raw.EndsWith("'")
    if ($isDoubleQuoted -or $isSingleQuoted) {
        $raw = $raw.Substring(1, $raw.Length - 2).Trim()
    }

    $fromEnv = $raw.TrimEnd('/')
    if ($fromEnv -ne $expected) {
        throw 'LIVEKIT_URL does not match the Velts-Bad production LiveKit project.'
    }

    return $expected
}

function Test-PythonCommand([string]$CommandPath) {
    try {
        & $CommandPath --version *> $null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Get-PythonCommand {
    foreach ($name in @('py', 'python')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command -and (Test-PythonCommand $command.Source)) {
            return $command.Source
        }
    }

    throw 'No functional Python launcher found. Expected py or python.exe.'
}

function Get-FreeLoopbackPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
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

if ($normalizedIdentity -notmatch '^[a-z0-9][a-z0-9._@-]{0,63}$') {
    throw 'Invalid identity. Use 1-64 chars: a-z, 0-9, dot, underscore, @ or hyphen; first char must be alphanumeric.'
}

if ($allowed -notcontains $normalizedIdentity) {
    throw "Identity '$Identity' is not in the local Velts-Bad allowlist."
}

$room = "velts-bad-$([guid]::NewGuid().ToString('N').Substring(0, 16))"
$ttl = "${ValidForMinutes}m"
$agentName = 'velts-bad'
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

$pythonCommand = Get-PythonCommand
$clientDir = Join-Path $repoRoot 'scripts'
$clientFile = Join-Path $clientDir 'private-session-client.html'
if (-not (Test-Path $clientFile)) {
    throw 'Private session browser client is missing.'
}

$port = Get-FreeLoopbackPort
$serverArgs = @('-m', 'http.server', [string]$port, '--bind', '127.0.0.1')
$serverProcess = Start-Process `
    -FilePath $pythonCommand `
    -ArgumentList $serverArgs `
    -WorkingDirectory $clientDir `
    -WindowStyle Hidden `
    -PassThru

$serverParam = [uri]::EscapeDataString($liveKitUrl)
$roomParam = [uri]::EscapeDataString($room)
$clientUrl = "http://127.0.0.1:$port/private-session-client.html?server=$serverParam&room=$roomParam"

$ready = $false
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 150
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $clientUrl -TimeoutSec 2
        if ($response.StatusCode -eq 200) {
            $ready = $true
            break
        }
    }
    catch {
        if ($serverProcess.HasExited) {
            break
        }
    }
}

if (-not $ready) {
    if (-not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    }
    Set-Clipboard -Value '[cleared]'
    throw 'Local private-session client failed to start.'
}

Start-Process $clientUrl

Write-Host 'Private mic-only browser client opened.'
Write-Host "LiveKit URL: $liveKitUrl"
Write-Host "Room: $room"
Write-Host 'Token: copied to clipboard. Paste it into the password field and click Connect.'
Write-Host 'The page never requests camera access and clears the token field after connecting.'
Write-Host "Local web server PID: $($serverProcess.Id)"
Write-Host "After the test, stop it with: Stop-Process -Id $($serverProcess.Id)"
Write-Host "If needed, overwrite the clipboard with: Set-Clipboard -Value '[cleared]'"
