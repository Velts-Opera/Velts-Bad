# Velts-Bad

Agente de voz privado em português do Brasil, executado no LiveKit Cloud.

## Arquitetura

- LiveKit Cloud: transporte de áudio, salas, dispatch e runtime do agente.
- Groq: STT (`whisper-large-v3-turbo`) e LLM (`openai/gpt-oss-20b`).
- LiveKit Inference + Rime Coda: TTS em português com a voz técnica `estela`.
- Persona da assistente: `Stella`.
- Acesso: deny-by-default por `VELTS_BAD_ALLOWED_IDENTITIES`.
- Sessão: uma identity autorizada por sala; participantes adicionais são removidos e a saída do agente é restrita à identity vinculada.
- O Velts-Bad é independente do ChatFacil, Agente444 e Meta/WhatsApp.

## Privacidade

- `AgentSession.start(..., record=False)` desativa a gravação/upload da sessão pelo LiveKit Agent Observability.
- O worker conecta em `AutoSubscribe.AUDIO_ONLY`, evitando assinatura automática de vídeo.
- `RoomOptions(participant_identity=...)` vincula a pipeline de voz à identity autorizada selecionada antes da sessão iniciar.
- Participantes não autorizados ou adicionais são removidos; falha de remoção apaga a sala (fail closed).
- A faixa publicada pelo agente só pode ser assinada pela identity vinculada.
- Texto de entrada/saída do RoomIO está desativado.
- Logs de aplicação não registram identity, nome da sala, token ou conteúdo da conversa.
- A retenção de dados dos requests enviados diretamente ao Groq continua sujeita aos controles e à política da conta Groq; use Zero Data Retention no provedor quando esse nível de privacidade for necessário.

## Pré-requisitos

- LiveKit CLI (`lk`) autenticada no projeto correto.
- Git.
- Python funcional (`py` ou `python`) para servir o cliente local de teste em `127.0.0.1`.
- Python 3.13/`uv` para desenvolvimento local; CI valida o release em Linux.

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

O helper de sessão privada aceita apenas o endpoint de produção do projeto Velts-Bad: `wss://veltsapp-j8mqf7tp.livekit.cloud`. Não cole o conteúdo do `.env.local` em chats, issues, PRs ou logs.

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
3. gera uma sala aleatória `velts-bad-<16 hex>` por sessão;
4. fixa o dispatch no agente `velts-bad`;
5. cria token curto, 15 minutos por padrão;
6. permite publicar somente `microphone`;
7. define `canPublishData=false`;
8. nunca imprime o JWT nem o coloca na URL;
9. copia o JWT temporariamente para o clipboard;
10. inicia um servidor HTTP somente em `127.0.0.1` e abre o cliente local mic-only;
11. fixa o cliente no endpoint LiveKit de produção e rejeita sala fora do formato esperado;
12. nunca solicita câmera e limpa o campo de token após conectar.

No navegador, clique em **Conectar**. Se a leitura automática do clipboard for bloqueada, cole o token apenas no campo de fallback exibido pela página. Após a conexão, o cliente tenta sobrescrever o clipboard automaticamente; se necessário, use:

```powershell
Set-Clipboard -Value '[cleared]'
```

Ao terminar, pare o servidor local usando o PID exibido pelo helper:

```powershell
Stop-Process -Id <PID>
```

Não use `meet.livekit.io` nem o antigo Agents Playground para esse fluxo privado.

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

Esse gate de deploy reduz o risco de um push direto na `main`, mas não substitui proteção de branch no GitHub. A `main` deve ser protegida por ruleset/branch protection com PR e `CI` obrigatórios quando essa governança estiver disponível.

## Validação pós-deploy

```powershell
lk agent status --id CA_GTdmGaEPnJy3 .
lk agent logs
lk agent secrets --id CA_GTdmGaEPnJy3 .
```

Critérios mínimos:

- status `Running` e réplica saudável;
- identity autorizada ouve a saudação da Stella e completa STT -> LLM -> TTS;
- identity não autorizada é removida e não inicia sessão de IA;
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
