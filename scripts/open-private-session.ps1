param(
    [Parameter(Mandatory = $true)]
    [string]$Identity,

    [ValidateRange(5, 30)]
    [int]$ValidForMinutes = 15
)

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

function Get-AllowedIdentitiesRaw([hashtable]$Values) {
    $raw = [string]$Values['VELTS_BAD_ALLOWED_IDENTITIES']
    if (-not $raw) {
        return ''
    }

    # Recover from an old PowerShell Add-Content edge case where the next env
    # assignment was appended to the allowlist because the file lacked a final
    # newline, e.g. "veltsVELTS_BAD_LLM_MODEL=...". The deployment helper has
    # historically handled this exact malformed local file, so the session
    # helper must interpret it consistently rather than denying a valid user.
    $joinedMarker = 'VELTS_BAD_LLM_MODEL='
    $joinedIndex = $raw.IndexOf($joinedMarker, [System.StringComparison]::Ordinal)
    if ($joinedIndex -ge 0) {
        $raw = $raw.Substring(0, $joinedIndex).Trim()
    }

    return $raw
}

function ConvertTo-NativeJsonArgument([string]$Json) {
    # Windows PowerShell 5.x (PSEdition Desktop) strips unescaped inner double
    # quotes when marshaling string arguments to native executables. LiveKit's
    # --grant flag expects real JSON, so escape the quotes for that legacy
    # command-line marshaler. PowerShell 7+ passes the JSON string correctly.
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        return $Json.Replace('"', '\"')
    }

    return $Json
}

if (-not (Get-Command lk -ErrorAction SilentlyContinue)) {
    throw 'LiveKit CLI (lk) não encontrado.'
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git não encontrado.'
}

if (-not (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
    throw 'Set-Clipboard não está disponível neste PowerShell.'
}

$repoRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) {
    throw 'Execute este script dentro do repositório Git do Velts-Bad.'
}
Set-Location $repoRoot

$envValues = Read-DotEnv '.env.local'
$liveKitUrl = ([string]$envValues['LIVEKIT_URL']).Trim()
if (-not $liveKitUrl -or $liveKitUrl -notmatch '^wss://') {
    throw 'LIVEKIT_URL ausente ou inválida em .env.local. Esperado wss://...'
}

$allowedRaw = Get-AllowedIdentitiesRaw $envValues
if (-not $allowedRaw) {
    throw 'VELTS_BAD_ALLOWED_IDENTITIES ausente ou vazio em .env.local.'
}

$allowed = @(
    $allowedRaw.Split(',') |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ }
)

$normalizedIdentity = $Identity.Trim().ToLowerInvariant()
if (-not $normalizedIdentity) {
    throw 'Identity vazia não é permitida.'
}

# Keep CLI values unambiguous and predictable. In particular, identities may
# never start with "-", contain whitespace, quotes, shell metacharacters, or
# exceed the small application-level identifier budget.
if ($normalizedIdentity -notmatch '^[a-z0-9][a-z0-9._@-]{0,63}$') {
    throw 'Identity inválida. Use 1-64 caracteres: a-z, 0-9, ponto, sublinhado, @ ou hífen; o primeiro caractere deve ser alfanumérico.'
}

if ($allowed -notcontains $normalizedIdentity) {
    throw "Identity '$Identity' não está na allowlist local do Velts-Bad."
}

$room = "velts-bad-$([guid]::NewGuid().ToString('N').Substring(0, 16))"
$ttl = "${ValidForMinutes}m"
$agentName = 'velts-bad'
$playgroundUrl = 'https://agents-playground.livekit.io/'

# --allow-source microphone restricts publish tracks to the microphone.
# LiveKit defaults canSubscribe=true and canUpdateOwnMetadata=false. The one
# additional permission that must be overridden is canPublishData, whose
# default follows canPublish and would otherwise be true.
$grantJson = '{"canPublishData":false}'
$grant = ConvertTo-NativeJsonArgument $grantJson

Write-Host "Preparando sessão privada [$room] para identity [$normalizedIdentity]..."
Write-Host "Token temporário: $ttl. O valor não será impresso."

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
    throw "LiveKit CLI encerrou com código $LASTEXITCODE ao criar o token privado."
}

$tokenCandidates = @(
    $tokenOutput |
        ForEach-Object { ([string]$_).Trim() } |
        Where-Object { $_ -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' }
)

if ($tokenCandidates.Count -ne 1) {
    throw 'O LiveKit CLI não retornou exatamente um JWT válido. Token não copiado.'
}

$token = $tokenCandidates[0]
Set-Clipboard -Value $token
Start-Process $playgroundUrl

Write-Host "Agents Playground aberto."
Write-Host "LiveKit URL: $liveKitUrl"
Write-Host "Sala: $room"
Write-Host "Token: copiado para a área de transferência; cole no campo de token do Playground."
Write-Host "Mantenha a câmera DESATIVADA e habilite somente o microfone."
Write-Host "Depois de conectar, limpe a área de transferência com: Set-Clipboard -Value ''"
