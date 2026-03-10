FROM node:20-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends chromium iproute2 \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g openclaw \
    && useradd -m -s /bin/bash openclaw \
    && mkdir -p /app/data && chown openclaw:openclaw /app/data

COPY <<'ENTRY' /usr/local/bin/entrypoint.sh
#!/bin/sh
set -eu

USERS=$(echo "$ALLOWED_TELEGRAM_USERS" | sed 's/[[:space:]]*,[[:space:]]*/", "/g; s/^/"/; s/$/"/')
N=1
while ss -tlnH 2>/dev/null | grep -q ":$((9200 + N)) "; do
  N=$((N + 1))
done
DEBUG_PORT=$((9200 + N))
GATEWAY_PORT=$((18700 + N))
echo "[${INSTANCE_NAME:-OpenClaw}] debug=:${DEBUG_PORT} gateway=:${GATEWAY_PORT}"

cat > /tmp/openclaw.json <<CFG
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
    "args": ["--remote-debugging-port=${DEBUG_PORT}", "--remote-debugging-address=0.0.0.0"]
  },
  "gateway": { "port": ${GATEWAY_PORT} }
}
CFG

exec openclaw gateway start --config /tmp/openclaw.json
ENTRY

RUN chmod +x /usr/local/bin/entrypoint.sh

USER openclaw
WORKDIR /app/data
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
