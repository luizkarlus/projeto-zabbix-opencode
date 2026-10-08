#!/usr/bin/env bash
# ==============================================================================
# bootstrap.sh — provisiona o laboratório completo:
#   Zabbix 7.0 + MCP + Ollama + Open WebUI + Laya (JEV) + WA-AKG
#
# Uso:
#   ./scripts/bootstrap.sh              provisionamento completo
#   ./scripts/bootstrap.sh --sem-modelo  não baixa o modelo do Ollama
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PULL_MODEL=1
[[ "${1:-}" == "--sem-modelo" ]] && PULL_MODEL=0

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ⚠ %s\033[0m\n' "$*"; }

# ------------------------------------------------------------------ deps
say "Verificando dependências"
for c in docker curl python3 openssl; do
  command -v "$c" >/dev/null || { echo "FALTA: $c"; exit 1; }
done
docker compose version >/dev/null || { echo "FALTA: docker compose plugin"; exit 1; }
ok "docker, compose, curl, python3, openssl"

# ------------------------------------------------------------------ .env
if [[ ! -f .env ]]; then
  say "Gerando .env com segredos aleatórios"
  sed \
    -e "s/^ZBX_DB_PASSWORD=.*/ZBX_DB_PASSWORD=$(openssl rand -hex 16)/" \
    -e "s/^WA_MYSQL_ROOT_PASSWORD=.*/WA_MYSQL_ROOT_PASSWORD=$(openssl rand -hex 16)/" \
    -e "s/^WA_AUTH_SECRET=.*/WA_AUTH_SECRET=$(openssl rand -base64 32 | tr -d '\n')/" \
    -e "s/^WA_ADMIN_PASSWORD=.*/WA_ADMIN_PASSWORD=$(openssl rand -hex 8)/" \
    .env.example > .env
  ok ".env criado"
else
  ok ".env já existe"
fi
set -a; source .env; set +a

# ------------------------------------------------- segredos MCP (tokens)
say "Gerando tokens do MCP server"
read -r MCP_TOKEN MCP_TOKEN_HASH <<<"$(python3 - <<'EOF'
import secrets, hashlib
t = 'zmcp_' + secrets.token_hex(32)
print(t, hashlib.sha256(t.encode()).hexdigest())
EOF
)"
ADMIN_PORTAL_PASS="$(openssl rand -hex 8)"
ADMIN_HASH="$(ADMIN_PORTAL_PASS="$ADMIN_PORTAL_PASS" python3 - <<'EOF'
import hashlib, os
s = os.urandom(16)
h = hashlib.scrypt(os.environ["ADMIN_PORTAL_PASS"].encode(), salt=s,
                   n=16384, r=8, p=1, dklen=32)
print(f"scrypt:16384:8:1${s.hex()}${h.hex()}")
EOF
)"
WA_API_KEY="wak_$(openssl rand -hex 24)"
ok "tokens gerados"

# ------------------------------------------------- config.toml do MCP
if [[ ! -f config/zabbix-mcp/config.toml ]]; then
  say "Renderizando config/zabbix-mcp/config.toml"
  # __ZABBIX_API_TOKEN__ fica como placeholder: o zabbix_bootstrap.py
  # substitui pelo token real criado via API do Zabbix.
  sed \
    -e "s/__MCP_TOKEN_HASH__/${MCP_TOKEN_HASH}/" \
    -e "s/__ADMIN_HASH__/${ADMIN_HASH//\//\\/}/" \
    config/zabbix-mcp/config.toml.example > config/zabbix-mcp/config.toml
  ok "config.toml criado"
else
  ok "config.toml já existe"
fi

# ------------------------------------------------------------------ build
say "Construindo imagens locais (WA-AKG, MCP, Laya) — pode demorar na 1ª vez"
docker compose build --quiet

say "Baixando imagens externas"
docker compose pull --quiet postgres zabbix-server zabbix-web zabbix-agent \
  wa-akg-db ollama open-webui grafana 2>/dev/null || true

# ------------------------------------------------- sobe tudo menos o MCP
say "Subindo Zabbix, Grafana, WA-AKG, Ollama, Open WebUI e Laya"
docker compose up -d postgres zabbix-server zabbix-web zabbix-agent \
  wa-akg-db wa-akg ollama open-webui laya-mcp grafana
ok "containers no ar"

# ------------------------------------------------- provisiona o Zabbix
say "Provisionando o Zabbix via API"
python3 scripts/zabbix_bootstrap.py \
  --zbx-url http://localhost:8080 \
  --config "$ROOT/config/zabbix-mcp/config.toml" \
  --wa-api-key "$WA_API_KEY" \
  --wa-url http://wa-akg:3000

# Se o token ainda for placeholder, algo falhou acima.
if grep -q "__ZABBIX_API_TOKEN__" config/zabbix-mcp/config.toml; then
  warn "token ainda pendente — verifique a saída acima"
fi

# ------------------------------------------------- sobe o MCP server
say "Subindo o Zabbix MCP server"
docker compose up -d zabbix-mcp
sleep 5
docker compose ps zabbix-mcp --format '{{.Name}} {{.Status}}'

# ------------------------------------------------- WA-AKG: admin + api key
say "Configurando admin e API key do WA-AKG"
for i in $(seq 1 60); do
  if curl -sf http://localhost:3000/api/health >/dev/null 2>&1 \
  || curl -sf http://localhost:3000 >/dev/null 2>&1; then break; fi
  sleep 5
done
docker exec zlab-wa node scripts/setup-admin.js \
  "$WA_ADMIN_EMAIL" "$WA_ADMIN_PASSWORD" || warn "setup-admin falhou (o usuário já existe?)"
for i in $(seq 1 30); do
  if docker exec zlab-wa-db mysql -uroot -p"$WA_MYSQL_ROOT_PASSWORD" wa_akg \
      -e "UPDATE User SET apiKey='${WA_API_KEY}' WHERE email='${WA_ADMIN_EMAIL}';" \
      2>/dev/null; then break; fi
  sleep 4
done
ok "API key do WA-AKG definida"

# ------------------------------------------------- modelo do Ollama
if [[ "$PULL_MODEL" == "1" ]]; then
  say "Baixando modelo ${OLLAMA_MODEL} no Ollama (em background)"
  nohup docker exec zlab-ollama ollama pull "$OLLAMA_MODEL" \
    > /tmp/opencode/ollama-pull.log 2>&1 &
  ok "pull iniciado (acompanhe: docker exec zlab-ollama ollama list)"
fi

# ------------------------------------------------- credenciais
say "Gravando config/credenciais.txt"
cat > config/credenciais.txt <<EOF
=====================================================================
 ZABBIX AI LAB — CREDENCIAIS (gerado em $(date))
=====================================================================

 Zabbix UI ............. http://localhost:8080
                         usuário: Admin   senha: zabbix  (TROQUE!)

 MCP server (initMAX) .. http://localhost:8081/mcp
   Bearer token ........ ${MCP_TOKEN}
   Admin portal ........ http://localhost:9091
                         usuário: admin   senha: ${ADMIN_PORTAL_PASS}

 Open WebUI ............ http://localhost:3001
                         (1º acesso cria a conta de administrador)

 Grafana ............... http://localhost:3002
                         usuário: admin   senha: ${GRAFANA_ADMIN_PASSWORD}
                         (datasource Zabbix já provisionado)

 Ollama ................ http://localhost:11434  (modelo: ${OLLAMA_MODEL})

 Laya (JEV) ............ http://localhost:8001/docs  (OpenAPI via mcpo)

 WA-AKG ................ http://localhost:3000
                         e-mail: ${WA_ADMIN_EMAIL}
                         senha:  ${WA_ADMIN_PASSWORD}
   API key (X-API-Key) . ${WA_API_KEY}
   Swagger ............. http://localhost:3000/docs
                         (usuário: admin / senha: ${WA_ADMIN_PASSWORD})

 Senhas de banco ....... ver .env
=====================================================================
EOF
chmod 600 config/credenciais.txt

say "LABORATÓRIO NO AR 🚀"
cat <<EOF

  Próximos passos manuais:

  1. WHATSAPP — pareie seu número no WA-AKG:
     http://localhost:3000 → Sessions → New Session → escaneie o QR Code
     Depois: Alertas → Media types → WhatsApp → preencha SESSION_ID
     Detalhes: docs/02-whatsapp.md

  2. IA — conecte os MCP servers no Open WebUI:
     http://localhost:3001 → Admin → Settings → Tools
     Detalhes: docs/03-openwebui.md

  3. TESTE — dispare um alerta e receba no WhatsApp:
     docs/04-testes.md

  Credenciais completas: config/credenciais.txt
EOF
