FROM node:20-bookworm-slim@sha256:a82f40540f5959e0003fb7b3c0f80490def2927be8bdbee7e3e0ac65cce3be92

RUN apt-get update && apt-get install -y --no-install-recommends chromium iproute2 \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g openclaw@2026.3.8 \
    && useradd -m -s /bin/bash openclaw \
    && mkdir -p /app/data /run/openclaw \
    && chown openclaw:openclaw /app/data /run/openclaw

COPY <<'ENTRY' /usr/local/bin/entrypoint.sh
#!/bin/sh
set -eu

# --- validacao de inputs ---
: "${TELEGRAM_BOT_TOKEN:?required}"
: "${ALLOWED_TELEGRAM_USERS:?required}"

case "$TELEGRAM_BOT_TOKEN" in
  *[!A-Za-z0-9:_-]*) echo "ERRO: TELEGRAM_BOT_TOKEN contem caracteres invalidos" >&2; exit 1 ;;
esac

case "${INSTANCE_NAME:-OpenClaw}" in
  *[\"\\$\`\\\\]*) echo "ERRO: INSTANCE_NAME contem caracteres invalidos" >&2; exit 1 ;;
esac
# bloqueia caracteres de controle (newlines, tabs, etc)
case "${INSTANCE_NAME:-OpenClaw}" in
  *"$(printf '\n')"*|*"$(printf '\r')"*|*"$(printf '\t')"*)
    echo "ERRO: INSTANCE_NAME contem caracteres de controle" >&2; exit 1 ;;
esac

case "$ALLOWED_TELEGRAM_USERS" in
  *[!0-9,\ ]*) echo "ERRO: ALLOWED_TELEGRAM_USERS deve conter apenas IDs numericos e virgulas" >&2; exit 1 ;;
esac

USERS=$(echo "$ALLOWED_TELEGRAM_USERS" | sed 's/[[:space:]]*,[[:space:]]*/", "/g; s/^/"/; s/$/"/')

DEBUG_PORT=9201
GATEWAY_PORT=18701
echo "[${INSTANCE_NAME:-OpenClaw}] debug=:${DEBUG_PORT} gateway=:${GATEWAY_PORT}"

umask 077
cat > /run/openclaw/config.json <<CFG
{
  "identity": { "name": "${INSTANCE_NAME:-OpenClaw}", "emoji": "🦞" },
  "agents": {
    "defaults": {
      "model": { "primary": "openai/gpt-4o", "fallbacks": ["openai/gpt-4-turbo"] }
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "${TELEGRAM_BOT_TOKEN}",
      "dmPolicy": "allowlist",
      "allowFrom": [${USERS}]
    }
  },
  "auth": {
    "profiles": { "openai:sso": { "mode": "sso" } },
    "order": { "openai": ["openai:sso"] }
  },
  "browser": {
    "args": ["--disable-setuid-sandbox", "--remote-debugging-port=${DEBUG_PORT}", "--remote-debugging-address=127.0.0.1"]
  },
  "gateway": { "port": ${GATEWAY_PORT} }
}
CFG

exec openclaw gateway start --config /run/openclaw/config.json
ENTRY

RUN chmod +x /usr/local/bin/entrypoint.sh

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD ss -tlnH | grep -q ":18701 " || exit 1

USER openclaw
WORKDIR /app/data
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
