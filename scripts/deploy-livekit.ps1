param(
    [string]$AgentId = 'CA_GTdmGaEPnJy3',
    [switch]$AllowNonMain
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

function Add-OptionalSecret(
    [System.Collections.Generic.List[string]]$Lines,
    [hashtable]$Values,
    [string]$Name
) {
    $value = [string]$Values[$Name]
    if ($value) {
        $Lines.Add("$Name=$value")
    }
}

if (-not (Get-Command lk -ErrorAction SilentlyContinue)) {
    throw 'LiveKit CLI (lk) não encontrado.'
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git não encontrado.'
}

$repoRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) {
    throw 'Execute este script dentro do repositório Git do Velts-Bad.'
}
Set-Location $repoRoot

$currentBranch = (& git branch --show-current).Trim()
if (-not $AllowNonMain -and $currentBranch -ne 'main') {
    throw "Deploy de produção bloqueado na branch '$currentBranch'. Faça merge e execute na main, ou use -AllowNonMain conscientemente para teste controlado."
}

$dirtyTree = & git status --porcelain
if ($dirtyTree) {
    throw 'Deploy bloqueado: o working tree contém arquivos alterados ou não rastreados. Commit, remova ou ignore antes de implantar.'
}

if (-not $AllowNonMain) {
    & git fetch origin main --quiet
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível atualizar origin/main antes do deploy.'
    }

    $headSha = (& git rev-parse HEAD).Trim()
    $originMainSha = (& git rev-parse origin/main).Trim()
    if ($headSha -ne $originMainSha) {
        throw 'Deploy bloqueado: a main local não corresponde a origin/main. Execute git pull --ff-only.'
    }
}

$envValues = Read-DotEnv '.env.local'

if (-not $envValues['GROQ_API_KEY']) {
    throw 'GROQ_API_KEY ausente em .env.local.'
}

$allowedIdentities = [string]$envValues['VELTS_BAD_ALLOWED_IDENTITIES']
$llmModel = [string]$envValues['VELTS_BAD_LLM_MODEL']

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

if (-not (Test-Path 'livekit.toml')) {
    Write-Host "Regenerating local LiveKit config for existing agent [$AgentId]..."
    & lk agent config --id $AgentId .
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível gerar livekit.toml para o agente existente [$AgentId]."
    }
}

$configText = Get-Content 'livekit.toml' -Raw
if ($configText -notmatch [regex]::Escape($AgentId)) {
    throw "livekit.toml não aponta para o agente esperado [$AgentId]. Deploy abortado."
}

$tempSecrets = Join-Path ([System.IO.Path]::GetTempPath()) ("velts-bad-secrets-" + [guid]::NewGuid().ToString('N') + '.env')

try {
    $secretLines = New-Object 'System.Collections.Generic.List[string]'
    $secretLines.Add("GROQ_API_KEY=$($envValues['GROQ_API_KEY'])")
    $secretLines.Add("VELTS_BAD_ALLOWED_IDENTITIES=$allowedIdentities")
    $secretLines.Add("VELTS_BAD_LLM_MODEL=$llmModel")

    @(
        'VELTS_BAD_STT_MODEL',
        'VELTS_BAD_STT_LANGUAGE',
        'VELTS_BAD_TTS_MODEL',
        'VELTS_BAD_TTS_VOICE',
        'VELTS_BAD_TTS_LANGUAGE',
        'VELTS_BAD_PARTICIPANT_WAIT_SECONDS',
        'VELTS_BAD_MAX_SESSION_SECONDS',
        'VELTS_BAD_MAX_TURN_WORDS',
        'VELTS_BAD_MAX_TURN_SECONDS',
        'VELTS_BAD_MAX_COMPLETION_TOKENS'
    ) | ForEach-Object { Add-OptionalSecret $secretLines $envValues $_ }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($tempSecrets, $secretLines, $utf8NoBom)

    $secretNames = $secretLines | ForEach-Object { ($_ -split '=', 2)[0] }
    Write-Host ('Prepared LiveKit secret names: ' + ($secretNames -join ', '))

    # Stage required values without deleting anything the currently-running
    # version might still depend on. This minimizes blast radius if the new
    # build fails before rollout completes.
    Write-Host "Staging application secrets for existing agent [$AgentId]..."
    & lk agent update-secrets --id $AgentId --secrets-file $tempSecrets .
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao preparar secrets do agente existente [$AgentId]. Deploy abortado."
    }

    Write-Host "Deploying existing Velts-Bad agent [$AgentId] from branch [$currentBranch]..."
    & lk agent deploy .
    if ($LASTEXITCODE -ne 0) {
        throw "LiveKit CLI encerrou com código $LASTEXITCODE durante o deploy."
    }

    # Only after a successful deploy do we remove stale application keys such as
    # the retired VELTS_BAD_ALLOW_CONSOLE flag. LIVEKIT_* are managed separately
    # by LiveKit Cloud and are not part of this secret set.
    Write-Host "Removing obsolete application secrets after successful deploy..."
    & lk agent update-secrets --id $AgentId --secrets-file $tempSecrets --overwrite .
    if ($LASTEXITCODE -ne 0) {
        throw 'Deploy concluído, mas a limpeza final de secrets falhou. Não considerar o release validado.'
    }

    Write-Host "Checking agent status after deploy and secret cleanup..."
    & lk agent status --id $AgentId .
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível consultar o status final do agente.'
    }
}
finally {
    if (Test-Path $tempSecrets) {
        Remove-Item $tempSecrets -Force
    }
}
