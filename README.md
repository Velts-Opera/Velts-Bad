# Velts-Bad

Agente de voz privado em português do Brasil, executado no LiveKit Cloud.

## Arquitetura

- LiveKit Cloud: transporte de áudio, salas, dispatch e runtime do agente.
- Groq: STT (`whisper-large-v3-turbo`) e LLM (`openai/gpt-oss-20b`).
- LiveKit Inference + Rime Coda: TTS em português com a voz `estela`.
- Acesso: deny-by-default por `VELTS_BAD_ALLOWED_IDENTITIES`.
- Sessão: uma identity autorizada por sala; participantes adicionais são removidos e mídia é isolada à identity vinculada.
- O Velts-Bad é independente do ChatFacil, Agente444 e Meta/WhatsApp.

## Privacidade

- `AgentSession.start(..., record=False)` desativa a gravação/upload da sessão pelo LiveKit Agent Observability.
- O worker não auto-assina tracks; ele assina apenas áudio da identity autorizada.
- A faixa publicada pelo agente só pode ser assinada pela identity vinculada.
- Texto de entrada/saída do RoomIO está desativado.
- Logs de aplicação não registram identity, nome da sala, token ou conteúdo da conversa.
- A retenção de dados dos requests enviados diretamente ao Groq continua sujeita aos controles e à política da conta Groq; use Zero Data Retention no provedor quando esse nível de privacidade for necessário.

## Pré-requisitos

- LiveKit CLI (`lk`) autenticada no projeto correto.
- Git.
- Python 3.13/`uv` apenas para desenvolvimento local; CI valida o release em Linux.

## Segredos

Nunca commite `.env.local`, tokens, chaves ou `livekit.toml` gerado localmente.

Para atualizar as credenciais locais do projeto LiveKit:

```powershell
lk app env -w -d .env.local
notepad .env.local
```

Além das variáveis `LIVEKIT_*`, configure pelo menos:

```text
GROQ_API_KEY=<secret>
VELTS_BAD_ALLOWED_IDENTITIES=velts
VELTS_BAD_LLM_MODEL=openai/gpt-oss-20b
```

Não cole o conteúdo do `.env.local` em chats, issues, PRs ou logs.

## Dependências e testes

O `uv.lock` é obrigatório. Em uma máquina onde a execução de virtualenv não seja bloqueada pela política do sistema:

```powershell
uv sync --locked --extra dev
uv pip check
uv run --locked pip-audit --progress-spinner off
uv run --locked ruff check src tests scripts
uv run --locked mypy src tests scripts
uv run --locked pytest -q
uv run --locked python scripts/check_secrets.py
```

O GitHub Actions também executa esses gates, valida a sintaxe dos scripts PowerShell, constrói a imagem Docker e executa smoke test dentro da imagem.

## Abrir uma sessão privada

Use uma sala nova para cada conversa:

```powershell
.\scripts\open-private-session.ps1 -Identity velts
```

O helper:

1. exige que a identity esteja em `VELTS_BAD_ALLOWED_IDENTITIES`;
2. aceita somente identities em formato seguro de 1–64 caracteres;
3. gera uma sala aleatória por sessão;
4. fixa o dispatch no agente `velts-bad`;
5. cria token curto, 15 minutos por padrão;
6. permite publicar somente `microphone`;
7. permite assinar a voz do agente;
8. proíbe publicação de data e alteração de metadata;
9. gera o JWT sem imprimi-lo, valida o formato e copia o token para a área de transferência;
10. abre o LiveKit Agents Playground, que é adequado para teste de agentes sem exigir publicação de câmera.

No Playground, cole o token copiado, mantenha a câmera desativada e habilite somente o microfone. Após conectar, sobrescreva a área de transferência com um valor inofensivo:

```powershell
Set-Clipboard -Value '[cleared]'
```

O antigo `meet.livekit.io/custom` não deve ser usado com esse token mic-only porque o cliente de videoconferência tenta publicar câmera automaticamente. A validade do token limita a entrada inicial; a duração da conversa é controlada separadamente pelo agente. Não reutilize a mesma sala entre contatos.

## Deploy de produção

Deploy deve sair da `main`, com working tree limpo e exatamente sincronizado com `origin/main`:

```powershell
git switch main
git pull --ff-only
.\scripts\deploy-livekit.ps1
```

O helper de deploy:

1. bloqueia branch errada, árvore suja ou `main` desatualizada;
2. exige que o SHA exato da `main` possua um run GitHub Actions chamado `CI`, disparado por `push`, concluído com `success`;
3. falha fechado se não conseguir consultar o GitHub ou se o CI estiver ausente, pendente ou falho;
4. exige o agent ID de produção conhecido `CA_GTdmGaEPnJy3`;
5. regenera `livekit.toml` para esse agente se o arquivo local não existir;
6. prepara os secrets necessários sem apagar os usados pelo runtime atual;
7. faz rolling deploy do agente existente;
8. somente após deploy bem-sucedido remove secrets obsoletos por overwrite;
9. consulta o status final do agente.

O repositório é público e o gate de CI pode consultar a API do GitHub sem autenticação. Se o repositório se tornar privado, forneça um `GITHUB_TOKEN` somente-leitura no ambiente local. O script nunca imprime esse token.

Esse gate de deploy reduz o risco de um push direto na `main`, mas não substitui proteção de branch no GitHub. A `main` deve continuar sendo protegida por ruleset/branch protection com PR e `CI` obrigatórios.

## Validação pós-deploy

```powershell
lk agent status --id CA_GTdmGaEPnJy3 .
lk agent logs
lk agent secrets --id CA_GTdmGaEPnJy3 .
```

Critérios mínimos:

- status `Running` e réplica saudável;
- identity autorizada recebe Estela + Groq;
- identity não autorizada não envia nem recebe mídia da sessão do agente;
- segundo participante é removido de uma sala já vinculada;
- logs de aplicação não contêm identity, room, token ou conteúdo da conversa;
- `VELTS_BAD_ALLOW_CONSOLE` não existe nos secrets;
- não existem secrets legados de WhatsApp/Meta no agente.

## Rollback

Quando o plano LiveKit oferecer rollback de versão:

```powershell
lk agent versions --id CA_GTdmGaEPnJy3
lk agent rollback --id CA_GTdmGaEPnJy3
```

Caso o rollback instantâneo não esteja disponível, reverta o commit problemático no Git, valide o CI e faça novo deploy.

## Regra de produção

Container iniciado não significa release aprovado. O release só é aceito depois de CI verde, build Docker, auditoria de dependências, scanner de segredos e E2E positivo + negativo contra o ambiente alvo.
