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

Crie o secret do bot token (recomendado em vez de env var):

```bash
echo "SEU_TOKEN_DO_BOTFATHER" > secrets/telegram_bot_token
chmod 600 secrets/telegram_bot_token
```

### 4. Docker Content Trust (opcional)

Ative a verificacao de assinaturas de imagens Docker:

```bash
echo 'export DOCKER_CONTENT_TRUST=1' >> ~/.bashrc
source ~/.bashrc
```

### 5. Build

```bash
docker compose build
```

### 6. Login OpenAI (uma vez)

```bash
docker compose run --rm -it --entrypoint openclaw openclaw auth login --provider openai
```

Token salvo no volume `auth`, compartilhado por todas as instancias.

### 7. Criar env da instancia

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

### 8. Subir uma instancia

```bash
docker network create claw-1-net
docker compose run -d --name claw-1 \
  --network claw-1-net \
  -p 127.0.0.1:9201:9201 -p 127.0.0.1:18701:18701 \
  --env-file .env.claw1 \
  openclaw
```

### 9. Mais instancias? Roda de novo

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

## Seguranca

- **Portas de debug (9201+):** O Chromium remote debugging da acesso total ao browser (cookies, sessoes, execucao de JS). **Sempre** use `127.0.0.1:` ao mapear portas com `-p`. Nunca exponha para a rede sem SSH tunnel.
- **Token do Telegram:** Use Docker secrets (`secrets/telegram_bot_token`) em vez de env var. O token fica montado em `/run/secrets/` dentro do container, sem exposicao em `/proc/1/environ`.
- **Volume `auth`:** Contem tokens de autenticacao do OpenAI. Proteja o host onde o Docker roda.
- **Multi-instancia:** Ao usar `docker compose run`, as portas do `docker-compose.yml` nao sao mapeadas automaticamente. Sempre passe `-p 127.0.0.1:PORTA:PORTA` explicitamente.
- **Permissoes:** `chmod 600 .env* secrets/*`
- **Container hardening:** Filesystem read-only, sem capabilities (`cap_drop: ALL`), `no-new-privileges`, limites de memoria/CPU/PIDs, usuario nao-root, perfil seccomp customizado, rede isolada.
- **Docker Content Trust:** Ative `DOCKER_CONTENT_TRUST=1` para verificar assinaturas de imagens.
- **Init process:** O compose usa `init: true` para evitar acumulo de processos zombie do Chromium.

### Hardening avancado (opcional)

**Restricao de egress (firewall no host):**

O container precisa acessar apenas a API do Telegram e do OpenAI. No host, restrinja o trafego de saida com iptables:

```bash
# Permitir DNS
sudo iptables -A DOCKER-USER -p udp --dport 53 -j ACCEPT
# Permitir HTTPS para APIs
sudo iptables -A DOCKER-USER -p tcp --dport 443 -j ACCEPT
# Bloquear todo o resto
sudo iptables -A DOCKER-USER -j DROP
```

Para uma restricao mais granular, use um proxy HTTPS (ex: squid) com whitelist de dominios (`api.telegram.org`, `api.openai.com`).

**User namespace remapping:**

Mapeia UIDs do container para UIDs nao-privilegiados no host, adicionando isolamento extra. Configure no daemon Docker (`/etc/docker/daemon.json`):

```json
{ "userns-remap": "default" }
```

Reinicie o Docker depois. Note que volumes existentes podem precisar de ajuste de permissoes.

**AppArmor profile:**

Um perfil AppArmor pode restringir acesso a caminhos de arquivo alem do que o seccomp oferece. Adicione ao compose:

```yaml
security_opt:
  - apparmor:openclaw-profile
```

Consulte a documentacao do Docker para criar profiles customizados.

## Scan de vulnerabilidades

```bash
./scan.sh
```

Roda trivy para verificar vulnerabilidades na imagem, no Dockerfile e secrets expostos. Recomendado rodar periodicamente e antes de cada deploy.

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
