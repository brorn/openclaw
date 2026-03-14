#!/bin/bash
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$DIR/config.json"
COMPOSE="$DIR/docker-compose.yml"
ENV_DIR="$DIR/envs"

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq necessario. Instale: sudo apt install jq"; exit 1; }

mkdir -p "$ENV_DIR"

# --- gerar tokens vazios e salvar no config.json ---
updated=false
tmp=$(mktemp)
cp "$CONFIG" "$tmp"
for i in $(seq 0 $(($(jq '.instances | length' "$tmp") - 1))); do
  token=$(jq -r ".instances[$i].OPENCLAW_GATEWAY_TOKEN // \"\"" "$tmp")
  if [ -z "$token" ]; then
    token=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
    tmp2=$(mktemp)
    jq ".instances[$i].OPENCLAW_GATEWAY_TOKEN = \"$token\"" "$tmp" > "$tmp2" && mv "$tmp2" "$tmp"
    updated=true
    echo "Token gerado para instancia $(jq -r ".instances[$i].id" "$tmp"): $token"
  fi
done
if [ "$updated" = true ]; then
  cp "$tmp" "$CONFIG"
  echo "config.json atualizado com tokens gerados."
fi
rm -f "$tmp"

count=$(jq '.instances | length' "$CONFIG")

if [ "$count" -eq 0 ]; then
  echo "Nenhuma instancia em config.json. Removendo tudo..."
  docker compose -f "$COMPOSE" down --remove-orphans 2>/dev/null || true
  exit 0
fi

# --- gerar env files por instancia ---
for i in $(seq 0 $((count - 1))); do
  id=$(jq -r ".instances[$i].id" "$CONFIG")
  gateway=$(jq -r ".instances[$i].OPENCLAW_GATEWAY_TOKEN // \"\"" "$CONFIG")
  allowed=$(jq -r ".instances[$i].ALLOWED_TELEGRAM_USERS // [] | if type == \"array\" then join(\",\") else . end" "$CONFIG")
  token=$(jq -r ".instances[$i].TELEGRAM_BOT_TOKEN // \"\"" "$CONFIG")
  agents=$(jq -c ".instances[$i].agents" "$CONFIG")

  cat > "$ENV_DIR/${id}.env" <<EOF
INSTANCE_NAME=${id}
TELEGRAM_BOT_TOKEN=${token}
ALLOWED_TELEGRAM_USERS=${allowed}
OPENCLAW_GATEWAY_TOKEN=${gateway}
AGENTS_JSON=${agents}
EOF
done

# --- gerar docker-compose.yml ---
cat > "$COMPOSE" <<'HEADER'
services:
  browser:
    image: chromedp/headless-shell:latest
    init: true
    restart: unless-stopped
    shm_size: "512m"
    mem_limit: 1G
    memswap_limit: 1G
    cpus: "1"
    read_only: true
    tmpfs:
      - /tmp:size=1G
      - /home/chrome:size=256M
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    pids_limit: 256
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    ports:
      - "127.0.0.1:9222:9222"
    networks:
      openclaw-net:
        ipv4_address: 172.28.0.10

HEADER

for i in $(seq 0 $((count - 1))); do
  id=$(jq -r ".instances[$i].id" "$CONFIG")
  gateway_port=$((18701 + i))

  cat >> "$COMPOSE" <<EOF
  ${id}:
    build: .
    init: true
    restart: unless-stopped
    depends_on:
      - browser
    environment:
      - BROWSER_CDP_URL=http://172.28.0.10:9222
    volumes:
      - ${id}_auth:/home/openclaw/.openclaw
      - ./secrets:/run/secrets:ro
    env_file: envs/${id}.env
    ports:
      - "127.0.0.1:${gateway_port}:18701"
    mem_limit: 1536M
    memswap_limit: 1536M
    cpus: "1"
    read_only: true
    tmpfs:
      - /tmp:size=1G
      - /run/openclaw:size=1M,uid=1001,gid=1001,mode=0700
    security_opt:
      - no-new-privileges:true
      - seccomp:seccomp-profile.json
    cap_drop:
      - ALL
    pids_limit: 256
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - openclaw-net

EOF
done

cat >> "$COMPOSE" <<'FOOTER'
networks:
  openclaw-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16

volumes:
FOOTER

for i in $(seq 0 $((count - 1))); do
  id=$(jq -r ".instances[$i].id" "$CONFIG")
  echo "  ${id}_auth:" >> "$COMPOSE"
done

echo "docker-compose.yml gerado com $count instancia(s)."

# --- detectar o que mudou ---
changed=""
for i in $(seq 0 $((count - 1))); do
  id=$(jq -r ".instances[$i].id" "$CONFIG")
  env_file="$ENV_DIR/${id}.env"
  env_bak="$ENV_DIR/${id}.env.prev"
  if [ ! -f "$env_bak" ] || ! diff -q "$env_file" "$env_bak" >/dev/null 2>&1; then
    changed="$changed $id"
  fi
  cp "$env_file" "$env_bak"
done

# --- detectar se precisa rebuild (Dockerfile mudou) ---
build_flag=""
dockerfile_hash="$ENV_DIR/.dockerfile.hash"
current_hash=$(sha256sum "$DIR/Dockerfile" | awk '{print $1}')
if [ ! -f "$dockerfile_hash" ] || [ "$(cat "$dockerfile_hash")" != "$current_hash" ]; then
  build_flag="--build"
  echo "$current_hash" > "$dockerfile_hash"
  echo "Dockerfile alterado — rebuild da imagem."
fi

echo "Aplicando..."
if [ -z "$changed" ] && [ -z "$build_flag" ]; then
  # nada mudou nos existentes, mas pode ter instancias novas/removidas
  docker compose -f "$COMPOSE" up -d --remove-orphans
elif [ -n "$build_flag" ]; then
  # Dockerfile mudou — rebuild e recriar tudo
  docker compose -f "$COMPOSE" up -d --remove-orphans $build_flag
else
  # recriar so os que mudaram (para pegar novo env/config)
  docker compose -f "$COMPOSE" up -d --remove-orphans --force-recreate $changed
fi
