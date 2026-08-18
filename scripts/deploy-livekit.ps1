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

if (-not $envValues['VELTS_BAD_ALLOWED_IDENTITIES']) {
    throw 'VELTS_BAD_ALLOWED_IDENTITIES ausente ou vazio. O Velts-Bad é deny-by-default.'
}

$tempSecrets = Join-Path ([System.IO.Path]::GetTempPath()) ("velts-bad-secrets-" + [guid]::NewGuid().ToString('N') + '.env')

try {
    $secretLines = @(
        "GROQ_API_KEY=$($envValues['GROQ_API_KEY'])",
        "VELTS_BAD_ALLOWED_IDENTITIES=$($envValues['VELTS_BAD_ALLOWED_IDENTITIES'])"
    )

    if ($envValues['GROQ_MODEL']) {
        $secretLines += "GROQ_MODEL=$($envValues['GROQ_MODEL'])"
    }

    if ($envValues['VELTS_BAD_LLM_MODEL']) {
        $secretLines += "VELTS_BAD_LLM_MODEL=$($envValues['VELTS_BAD_LLM_MODEL'])"
    }

    Set-Content -Path $tempSecrets -Value $secretLines -Encoding utf8

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
