# OpenClaw Docker — Pi 5

Uma imagem, quantas instancias quiser. Telegram + OpenAI via SSO.

## Setup

### 1. Git + Docker no Pi 5

```bash
sudo apt update && sudo apt install -y git

curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker
sudo apt install docker-compose-plugin
```

### 2. Clonar o projeto

```bash
git clone https://github.com/brorn/openclaw.git
cd openclaw
```

### 3. Configurar

```bash
nano .env
```

Troque `ALLOWED_TELEGRAM_USERS` pelo seu ID numerico ([@userinfobot](https://t.me/userinfobot)).

### 4. Build

```bash
docker compose build
```

### 5. Login OpenAI (uma vez)

```bash
docker compose run --rm -it --entrypoint openclaw openclaw auth login --provider openai
```

Token salvo no volume `auth`, compartilhado por todas as instancias.

### 6. Subir uma instancia

```bash
docker compose run -d --name claw-1 \
  -e TELEGRAM_BOT_TOKEN=<token_do_botfather> \
  -e INSTANCE_NAME="Claw 1" \
  openclaw
```

### 7. Mais instancias? Roda de novo

```bash
docker compose run -d --name claw-2 \
  -e TELEGRAM_BOT_TOKEN=<outro_token> \
  -e INSTANCE_NAME="Claw 2" \
  openclaw
```

Cada uma usa seu bot do Telegram. Repita quantas vezes quiser.

## Comandos

```bash
docker ps                                # status
docker logs -f claw-1                    # logs
docker restart claw-2                    # reiniciar
docker stop claw-1 && docker rm claw-1   # remover
docker stats                             # CPU/RAM
```

## Token expirou?

```bash
docker compose run --rm -it --entrypoint openclaw openclaw auth login --provider openai
docker restart claw-1 claw-2
```
