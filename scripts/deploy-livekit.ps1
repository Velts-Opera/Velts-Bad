$ErrorActionPreference = 'Stop'

function Read-DotEnv([string]$Path) {
    if (-not (Test-Path $Path)) {
        throw "Arquivo $Path não encontrado."
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

if (-not (Get-Command lk -ErrorAction SilentlyContinue)) {
    throw 'LiveKit CLI (lk) não encontrado.'
}

$envValues = Read-DotEnv '.env.local'

if (-not $envValues['GROQ_API_KEY']) {
    throw 'GROQ_API_KEY ausente em .env.local.'
}

$allowedIdentities = [string]$envValues['VELTS_BAD_ALLOWED_IDENTITIES']
$llmModel = [string]$envValues['VELTS_BAD_LLM_MODEL']
$allowConsole = [string]$envValues['VELTS_BAD_ALLOW_CONSOLE']

# Recover safely from a common PowerShell Add-Content edge case where a file
# without a trailing newline causes the next variable to be glued to the
# previous value.
$joinedMarker = 'VELTS_BAD_LLM_MODEL='
$joinedIndex = $allowedIdentities.IndexOf($joinedMarker, [System.StringComparison]::Ordinal)
if ($joinedIndex -ge 0) {
    if (-not $llmModel) {
        $llmModel = $allowedIdentities.Substring($joinedIndex + $joinedMarker.Length).Trim()
    }
    $allowedIdentities = $allowedIdentities.Substring(0, $joinedIndex).Trim()
}

if (-not $allowedIdentities) {
    throw 'VELTS_BAD_ALLOWED_IDENTITIES ausente ou vazio. O Velts-Bad é deny-by-default.'
}

if (-not $llmModel -or $llmModel -eq 'llama-3.3-70b-versatile') {
    $llmModel = 'openai/gpt-oss-20b'
}

# Keep the LiveKit Agent Console usable during development. The agent only
# bypasses the contact allowlist when BOTH this flag is true and the room name
# is a LiveKit console room (console-*).
if (-not $allowConsole) {
    $allowConsole = 'true'
}

$tempSecrets = Join-Path ([System.IO.Path]::GetTempPath()) ("velts-bad-secrets-" + [guid]::NewGuid().ToString('N') + '.env')

try {
    $secretLines = @(
        "GROQ_API_KEY=$($envValues['GROQ_API_KEY'])",
        "VELTS_BAD_ALLOWED_IDENTITIES=$allowedIdentities",
        "VELTS_BAD_LLM_MODEL=$llmModel",
        "VELTS_BAD_ALLOW_CONSOLE=$allowConsole"
    )

    # Windows PowerShell 5.1 writes a UTF-8 BOM with Set-Content -Encoding utf8.
    # LiveKit's dotenv parser rejects that BOM as part of the first variable name,
    # so write explicit UTF-8 without BOM.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($tempSecrets, $secretLines, $utf8NoBom)

    Write-Host 'Prepared LiveKit secrets: GROQ_API_KEY, VELTS_BAD_ALLOWED_IDENTITIES, VELTS_BAD_LLM_MODEL, VELTS_BAD_ALLOW_CONSOLE'

    if (Test-Path 'livekit.toml') {
        Write-Host 'Deploying new Velts-Bad version to LiveKit Cloud...'
        & lk agent deploy --secrets-file $tempSecrets .
    }
    else {
        Write-Host 'Creating Velts-Bad agent on LiveKit Cloud...'
        & lk agent create --secrets-file $tempSecrets .
    }

    if ($LASTEXITCODE -ne 0) {
        throw "LiveKit CLI encerrou com código $LASTEXITCODE."
    }
}
finally {
    if (Test-Path $tempSecrets) {
        Remove-Item $tempSecrets -Force
    }
}
