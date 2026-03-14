# OpenClaw Docker — Pi 5

Uma imagem, quantas instancias quiser. OpenAI Codex via OAuth SSO, Telegram opcional, browser remoto compartilhado.

## Setup

### 1. Dependencias

```bash
sudo apt update && sudo apt install -y git
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker
```

### 2. Clonar e configurar

```bash
git clone https://github.com/brorn/openclaw.git && cd openclaw
cp config.example.json config.json
nano config.json
```

```json
{
    "instances": [
        {
            "id": "minha_instancia",
            "agents": [{"name": "assistant", "subAgents": []}],
            "TELEGRAM_BOT_TOKEN": "",
            "ALLOWED_TELEGRAM_USERS": ""
        }
    ]
}
```

Telegram e opcional — deixe `TELEGRAM_BOT_TOKEN` vazio para rodar sem.

### 3. Login OpenAI (uma vez)

```bash
docker compose run --rm -it --entrypoint openclaw <id> configure --section auth
```

Siga o fluxo OAuth. O token fica no volume `auth`. **Nunca use `docker compose down -v`** — apaga os tokens.

### 4. Subir

```bash
./manage.sh
```

Le `config.json`, gera `docker-compose.yml`, sobe os containers. Portas atribuidas automaticamente (18701, 18702, ...).

Dashboard: `http://127.0.0.1:18701/__openclaw__/canvas/`

## Arquitetura

```
┌─────────────────────────────────────────────────┐
│  Docker network (172.28.0.0/16)                 │
│                                                 │
│  ┌──────────────┐    ┌────────────────────────┐ │
│  │   browser     │    │  instancia (openclaw)  │ │
│  │  Chrome 146   │◄───│  gateway :18701        │ │
│  │  CDP :9222    │    │  Brave API             │ │
│  │  IP: .0.10   │    │  SSH keys              │ │
│  └──────────────┘    └────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

- **Browser**: container `chromedp/headless-shell` compartilhado por todas as instancias via CDP
- **Secrets**: arquivos em `secrets/` montados em `/run/secrets/`, auto-exportados como env vars (ex: `brave_api_key` → `BRAVE_API_KEY`)
- **SSH keys**: `*_deploy` viram `GIT_SSH_COMMAND` automaticamente
- **Brave Search**: detectado via env `BRAVE_API_KEY` pelo `openclaw doctor --fix`
- **TOOLS.md**: gerado no workspace de cada agente com instrucoes de browser via CLI

## Secrets

Coloque arquivos em `secrets/`. No startup, o entrypoint:

| Arquivo | Vira |
|---|---|
| `*_deploy` | `GIT_SSH_COMMAND` com todas as keys |
| `*_deploy.pub`, `.gitkeep` | Ignorados |
| Qualquer outro | Env var em maiusculas (ex: `brave_api_key` → `BRAVE_API_KEY`) |

```bash
chmod 600 secrets/*
```

## Browser

Os agentes acessam o Chrome remoto via CLI (a ferramenta browser integrada nao funciona com CDP remoto). O `TOOLS.md` no workspace de cada agente instrui automaticamente.

### Login manual (2FA, CAPTCHA)

A porta CDP esta exposta em `127.0.0.1:9222`:

1. No Chrome do seu PC, abra `chrome://inspect`
2. Em "Discover network targets" > Configure, adicione `localhost:9222` (ou `<ip-do-pi>:9222` via SSH tunnel)
3. A aba aparece — clique **inspect** e faca login normalmente
4. Feche o DevTools — a sessao permanece no Chrome remoto
5. Peca pro agente continuar dali

Via SSH tunnel (acesso remoto):

```bash
ssh -L 9222:127.0.0.1:9222 user@<ip-do-pi>
```

## Telegram

**Token**: pegue com [@BotFather](https://t.me/BotFather), coloque no `config.json` ou como secret:

```bash
echo "123456:ABC-DEF" > secrets/telegram_bot_token && chmod 600 secrets/telegram_bot_token
```

**User ID**: envie qualquer mensagem para [@userinfobot](https://t.me/userinfobot). Multiplos: `"111,222,333"`

## Comandos

```bash
./manage.sh                                        # aplicar config.json
docker compose ps                                  # status
docker compose logs -f <id>                        # logs
docker compose logs <id> | grep "Gateway token"   # ver token
docker compose restart <id>                        # reiniciar
docker compose down                                # parar (SEM -v!)
```

## Seguranca

- Portas CDP/gateway em `127.0.0.1` — nunca exponha pra rede
- Secrets em `/run/secrets/` — nao aparecem em `docker inspect` nem `/proc/*/environ`
- Container: filesystem read-only, `cap_drop: ALL`, `no-new-privileges`, usuario nao-root, seccomp customizado, rede isolada, limites de RAM/CPU/PIDs
- `chmod 700 envs/ && chmod 600 secrets/*`

## Token expirou?

```bash
docker compose run --rm -it --entrypoint openclaw <id> configure --section auth
docker compose restart <id>
```

## Modelo

`openai-codex/gpt-5.4` (fallback: `openai-codex/gpt-4o`) via OAuth SSO — sem API key.
