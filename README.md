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
cp .env.example .env
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

### 6. Criar env da instancia

```bash
cp .env .env.claw1
nano .env.claw1
```

Adicione o token do bot:

```env
ALLOWED_TELEGRAM_USERS=123456789
TELEGRAM_BOT_TOKEN=<token_do_botfather>
INSTANCE_NAME=Claw 1
```

### 7. Subir uma instancia

```bash
docker network create claw-1-net
docker compose run -d --name claw-1 \
  --network claw-1-net \
  -p 127.0.0.1:9201:9201 -p 127.0.0.1:18701:18701 \
  --env-file .env.claw1 \
  openclaw
```

### 8. Mais instancias? Roda de novo

```bash
cp .env .env.claw2
nano .env.claw2
```

```bash
docker network create claw-2-net
docker compose run -d --name claw-2 \
  --network claw-2-net \
  -p 127.0.0.1:9202:9201 -p 127.0.0.1:18702:18701 \
  --env-file .env.claw2 \
  openclaw
```

Cada uma usa seu bot do Telegram e sua propria rede isolada. Incremente as portas externas (9203/18703, 9204/18704, ...) para cada instancia. Todas as portas ficam acessiveis apenas localmente (127.0.0.1).

## Comandos

```bash
docker ps                                # status
docker logs -f claw-1                    # logs
docker restart claw-2                    # reiniciar
docker stop claw-1 && docker rm claw-1   # remover
docker stats                             # CPU/RAM
```

## CAPTCHA ou login no browser?

O Chromium roda headless com remote debugging na porta interna 9201. Use a porta externa que voce mapeou com `-p` ao subir a instancia (ex: 9201 para claw-1, 9202 para claw-2).

A porta de debug so aceita conexoes locais (127.0.0.1). Para intervir (CAPTCHA, login manual, etc), abra um tunel SSH e acesse no navegador:

```bash
ssh -L 9201:127.0.0.1:9201 user@<ip-do-pi>
```

Depois abra `http://localhost:9201` no navegador.

## Token expirou?

```bash
docker compose run --rm -it --entrypoint openclaw openclaw auth login --provider openai
docker restart claw-1 claw-2
```
