FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends git openssh-client ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g openclaw@2026.3.8 \
    && printf '#!/bin/sh\necho "Chromium stub for remote CDP"\nexit 0\n' > /usr/bin/chromium \
    && chmod +x /usr/bin/chromium \
    && useradd -m -s /usr/sbin/nologin openclaw \
    && mkdir -p /app/data /run/openclaw /run/secrets /home/openclaw/.openclaw \
    && chown openclaw:openclaw /app/data /run/openclaw /run/secrets /home/openclaw/.openclaw

COPY <<'ENTRY' /usr/local/bin/entrypoint.sh
#!/bin/sh
set -eu

# --- validacao de ALLOWED_TELEGRAM_USERS ---
if [ -n "${ALLOWED_TELEGRAM_USERS:-}" ]; then
  case "$ALLOWED_TELEGRAM_USERS" in
    *[!0-9,\ ]*|*,,*|,*|*,) echo "ERRO: ALLOWED_TELEGRAM_USERS formato invalido (use: ID1,ID2)" >&2; exit 1 ;;
  esac
fi

# limite de tamanho (max 64 chars)
_name="${INSTANCE_NAME:-OpenClaw}"
if [ "${#_name}" -gt 64 ]; then
  echo "ERRO: INSTANCE_NAME muito longo (max 64 caracteres)" >&2; exit 1
fi

# whitelist: apenas caracteres imprimiveis
case "${INSTANCE_NAME:-OpenClaw}" in
  *[![:print:]]*) echo "ERRO: INSTANCE_NAME contem caracteres invalidos" >&2; exit 1 ;;
esac

# --- secrets como variaveis de ambiente ---
# SSH deploy keys: configuram GIT_SSH_COMMAND (multiplas keys via config)
_ssh_keys=""
for _f in /run/secrets/*_deploy; do
  [ -f "$_f" ] || continue
  _ssh_keys="$_ssh_keys -i $_f"
done
if [ -n "$_ssh_keys" ]; then
  export GIT_SSH_COMMAND="ssh$_ssh_keys -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes"
fi

# Demais secrets: exporta como ENV_VAR (nome em maiusculas)
# Ignora: *_deploy, *_deploy.pub, .gitkeep
for _f in /run/secrets/*; do
  [ -f "$_f" ] || continue
  _name="$(basename "$_f")"
  case "$_name" in
    *_deploy|*_deploy.pub|.gitkeep) continue ;;
  esac
  _var="$(echo "$_name" | tr '[:lower:].' '[:upper:]_')"
  export "$_var=$(cat "$_f")"
done

export GATEWAY_PORT=18701
if [ -n "${BROWSER_CDP_URL:-}" ]; then
  echo "[${INSTANCE_NAME:-OpenClaw}] browser=remote (${BROWSER_CDP_URL})"
fi
echo "[${INSTANCE_NAME:-OpenClaw}] gateway=:${GATEWAY_PORT}"

umask 077
node -e '
const fs = require("fs");
const name = process.env.INSTANCE_NAME || "OpenClaw";
const allowedUsers = (process.env.ALLOWED_TELEGRAM_USERS || "").split(",").map(s => s.trim()).filter(Boolean);
const agents = process.env.AGENTS_JSON ? JSON.parse(process.env.AGENTS_JSON) : [];

// --- agents list ---
const agentsList = agents.length
  ? agents.map((a, i) => ({
      id: a.name,
      ...(i === 0 ? { default: true } : {}),
      identity: { name: a.name, emoji: "\uD83E\uDD9E" },
      subagents: {
        allowAgents: a.subAgents && a.subAgents.length ? a.subAgents : ["*"]
      }
    }))
  : [{ id: "main", default: true, identity: { name: name, emoji: "\uD83E\uDD9E" }, subagents: { allowAgents: ["*"] } }];

// --- telegram: token no nivel da instancia ---
const channels = {};
const bindings = [];
const tokenRe = /^[A-Za-z0-9:_-]+$/;

const token = process.env.TELEGRAM_BOT_TOKEN || "";
if (token) {
  if (!tokenRe.test(token)) { console.error("ERRO: TELEGRAM_BOT_TOKEN invalido"); process.exit(1); }
  if (!allowedUsers.length) { console.error("ERRO: ALLOWED_TELEGRAM_USERS required quando ha token Telegram"); process.exit(1); }
  channels["telegram"] = {
    enabled: true,
    botToken: token,
    dmPolicy: "allowlist",
    allowFrom: allowedUsers
  };
  if (agentsList.length > 0) {
    bindings.push({ agentId: agentsList[0].id, match: { channel: "telegram" } });
  }
}

// --- browser: remote CDP ---
const browserCdpUrl = process.env.BROWSER_CDP_URL || "";
const browserConfig = browserCdpUrl ? {
  browser: {
    enabled: true,
    defaultProfile: "remote",
    profiles: {
      remote: {
        cdpUrl: browserCdpUrl,
        headless: true,
        noSandbox: true,
        color: "#00AA00"
      }
    }
  }
} : {};

const config = {
  agents: {
    defaults: {
      model: { primary: "openai-codex/gpt-5.4", fallbacks: ["openai-codex/gpt-4o"] },
      subagents: {
        maxSpawnDepth: 2,
        maxChildrenPerAgent: 5,
        maxConcurrent: 8
      }
    },
    list: agentsList
  },
  channels: channels,
  ...(bindings.length ? { bindings: bindings } : {}),
  ...browserConfig,
  auth: {
    profiles: { "openai:sso": { provider: "openai", mode: "oauth" } },
    order: { openai: ["openai:sso"] }
  },
  gateway: {
    port: parseInt(process.env.GATEWAY_PORT),
    mode: "local",
    controlUi: { allowedOrigins: ["http://127.0.0.1:" + process.env.GATEWAY_PORT] }
  }
};
const configDir = require("os").homedir() + "/.openclaw";
fs.mkdirSync(configDir, { recursive: true, mode: 0o700 });
fs.writeFileSync(configDir + "/openclaw.json", JSON.stringify(config, null, 2), { mode: 0o600 });

// --- TOOLS.md: instruções de browser para todos os agentes ---
const toolsMd = `# Browser

NÃO use a ferramenta browser integrada — ela não funciona neste ambiente.

Para acessar páginas web, use bash com os comandos CLI do OpenClaw:

\`\`\`bash
# abrir URL numa aba
openclaw browser open <url> --browser-profile remote --json

# capturar conteúdo da página (accessibility tree)
openclaw browser snapshot --format aria --browser-profile remote

# capturar screenshot
openclaw browser screenshot --browser-profile remote

# navegar na aba atual
openclaw browser navigate <url> --browser-profile remote

# listar abas abertas
openclaw browser tabs --browser-profile remote --json

# fechar aba
openclaw browser close <targetId> --browser-profile remote
\`\`\`

Sempre use \`--browser-profile remote\` em todos os comandos browser.
`;

// escrever TOOLS.md no workspace de cada agente
const os = require("os");
const wsBase = os.homedir() + "/.openclaw";
agentsList.forEach(a => {
  const wsDir = wsBase + "/workspace-" + a.id;
  fs.mkdirSync(wsDir, { recursive: true, mode: 0o700 });
  fs.writeFileSync(wsDir + "/TOOLS.md", toolsMd, { mode: 0o644 });
});
// workspace default tambem
fs.mkdirSync(wsBase + "/workspace", { recursive: true, mode: 0o700 });
fs.writeFileSync(wsBase + "/workspace/TOOLS.md", toolsMd, { mode: 0o644 });
'

OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)}"
export OPENCLAW_GATEWAY_TOKEN
echo "Gateway token: ${OPENCLAW_GATEWAY_TOKEN}"
openclaw doctor --fix 2>/dev/null || true
exec openclaw gateway run --bind lan --token "$OPENCLAW_GATEWAY_TOKEN"
ENTRY

RUN chmod +x /usr/local/bin/entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:18701',r=>{process.exit(r.statusCode<500?0:1)}).on('error',()=>process.exit(1))"

USER openclaw
WORKDIR /app/data
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
