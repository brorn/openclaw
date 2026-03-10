FROM node:20-bookworm-slim@sha256:a82f40540f5959e0003fb7b3c0f80490def2927be8bdbee7e3e0ac65cce3be92

RUN apt-get update && apt-get install -y --no-install-recommends chromium \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g openclaw@2026.3.8 \
    && useradd -m -s /usr/sbin/nologin openclaw \
    && mkdir -p /app/data /run/openclaw /run/secrets \
    && chown openclaw:openclaw /app/data /run/openclaw /run/secrets

COPY <<'ENTRY' /usr/local/bin/entrypoint.sh
#!/bin/sh
set -eu

# --- carregar secrets de arquivo (Docker secrets) ---
if [ -f /run/secrets/telegram_bot_token ]; then
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    echo "AVISO: TELEGRAM_BOT_TOKEN em env var ignorado; usando Docker secret" >&2
  fi
  TELEGRAM_BOT_TOKEN=$(cat /run/secrets/telegram_bot_token)
  export TELEGRAM_BOT_TOKEN
fi

# --- validacao de inputs ---
: "${TELEGRAM_BOT_TOKEN:?required — use Docker secret ou env var}"
: "${ALLOWED_TELEGRAM_USERS:?required}"

case "$TELEGRAM_BOT_TOKEN" in
  *[!A-Za-z0-9:_-]*) echo "ERRO: TELEGRAM_BOT_TOKEN contem caracteres invalidos" >&2; exit 1 ;;
esac

# limite de tamanho (max 64 chars)
_name="${INSTANCE_NAME:-OpenClaw}"
if [ "${#_name}" -gt 64 ]; then
  echo "ERRO: INSTANCE_NAME muito longo (max 64 caracteres)" >&2; exit 1
fi

# whitelist: apenas caracteres imprimiveis
case "${INSTANCE_NAME:-OpenClaw}" in
  *[![:print:]]*) echo "ERRO: INSTANCE_NAME contem caracteres invalidos" >&2; exit 1 ;;
esac

case "$ALLOWED_TELEGRAM_USERS" in
  *[!0-9,\ ]*|*,,*|,*|*,) echo "ERRO: ALLOWED_TELEGRAM_USERS formato invalido (use: ID1,ID2)" >&2; exit 1 ;;
esac

export DEBUG_PORT=9201
export GATEWAY_PORT=18701
echo "[${INSTANCE_NAME:-OpenClaw}] debug=:${DEBUG_PORT} gateway=:${GATEWAY_PORT}"

umask 077
node -e '
const fs = require("fs");
const config = {
  identity: { name: process.env.INSTANCE_NAME || "OpenClaw", emoji: "\uD83E\uDD9E" },
  agents: {
    defaults: {
      model: { primary: "openai/gpt-4o", fallbacks: ["openai/gpt-4-turbo"] }
    }
  },
  channels: {
    telegram: {
      enabled: true,
      botToken: process.env.TELEGRAM_BOT_TOKEN,
      dmPolicy: "allowlist",
      allowFrom: process.env.ALLOWED_TELEGRAM_USERS.split(",").map(s => s.trim())
    }
  },
  auth: {
    profiles: { "openai:sso": { mode: "sso" } },
    order: { openai: ["openai:sso"] }
  },
  browser: {
    args: [
      "--disable-setuid-sandbox",
      "--remote-debugging-port=" + process.env.DEBUG_PORT,
      "--remote-debugging-address=127.0.0.1"
    ]
  },
  gateway: { port: parseInt(process.env.GATEWAY_PORT) }
};
fs.writeFileSync("/run/openclaw/config.json", JSON.stringify(config, null, 2), { mode: 0o600 });
'

exec openclaw gateway start --config /run/openclaw/config.json
ENTRY

RUN chmod +x /usr/local/bin/entrypoint.sh

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:18701',r=>{process.exit(r.statusCode<500?0:1)}).on('error',()=>process.exit(1))"

USER openclaw
WORKDIR /app/data
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
