# 🧪 Zabbix AI Lab

Laboratório local completo: **Zabbix 7.0 LTS** monitorando infraestrutura, com
camada de **IA** (Ollama + Open WebUI) conversando com o Zabbix via **MCP**,
motor de decisão **System-1 JEV/Laya** para triagem/gate de alertas e envio de
alertas por **WhatsApp** através do gateway self-hosted **WA-AKG**.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Docker: zabbix-ai-lab                       │
│                                                                     │
│  Você (chat)   ┌────────────┐   MCP :8081   ┌──────────────────┐    │
│       ───────► │ Open WebUI │──────────────►│ Zabbix MCP       │    │
│                │   :3001    │               │ (initMAX, 237    │    │
│                    │   ▲     │  OpenAPI :8001│  tools)          │    │
│                    │   └─────────┐ ◄──────── │      │           │    │
│                    ▼             │           └──────┼───────────┘    │
│                ┌────────────┐   │                  │ API            │
│                │   Ollama   │   │                  ▼                │
│                │ llama3.1:8b│   │           ┌──────────────────┐    │
│                └────────────┘   │           │ Zabbix 7.0 LTS   │◄───┼───┐
│                                 │           │ web:8080 srv:10051    │   │
│                ┌────────────┐   │           │ + PostgreSQL     │    │   │
│                │ Laya (JEV) │───┘           │ + Agent demo     │    │   │
│                │ System-1   │               └──────┬───────────┘    │   │
│                │ :8001      │                      │ webhook        │   │
│                └────────────┘                      ▼                │   │
│                                     ┌──────────────────────────┐    │   │
│   WhatsApp ◄─── Baileys ─────────── │ WA-AKG gateway :3000     │    │   │
│   (seu cel)                         │ + MySQL                  │    │   │
│                                     └──────────────────────────┘    │   │
│                                                                     │   │
│                ┌────────────┐   plugin zabbix (API)                 │   │
│   Dashboards ──│  Grafana   │───────────────────────────────────────┼───┘
│                │   :3002    │
│                └────────────┘
└─────────────────────────────────────────────────────────────────────┘
```

## Componentes

| Peça | Projeto | Papel |
|---|---|---|
| Zabbix 7.0 LTS | oficial | server + web + PostgreSQL + agent demo |
| MCP | [initMAX/zabbix-mcp-server](https://github.com/initMAX/zabbix-mcp-server) | 237 tools da API do Zabbix via MCP HTTP |
| LLM | Ollama + llama3.1:8b | cérebro local, sem custo de API |
| Chat | Open WebUI | interface web; consome MCP nativamente |
| JEV/Laya | [fuleinist/laya_mcp](https://github.com/fuleinist/laya_mcp) + [ggmlc](https://github.com/monatis/ggmlc) | decisões tipadas em ~1s na CPU (triagem, gate de segurança, classificação) |
| WhatsApp | [mrifqidaffaaditya/WA-AKG](https://github.com/mrifqidaffaaditya/WA-AKG) | gateway REST ↔ WhatsApp (Baileys) |
| Grafana | oficial + [plugin Zabbix](https://grafana.com/grafana/plugins/alexanderzobnin-zabbix-app/) | dashboards; datasource provisionado automaticamente |

## Quick start

```bash
./scripts/bootstrap.sh
```

O script gera senhas aleatórias, constrói as imagens, sobe os containers,
provisiona o Zabbix via API (token do MCP, media type WhatsApp, host demo) e
grava tudo em **`config/credenciais.txt`**.

Depois restam 3 passos manuais:

1. **[Parear o WhatsApp](docs/02-whatsapp.md)** — QR Code no dashboard WA-AKG
2. **[Conectar a IA aos MCPs](docs/03-openwebui.md)** — Open WebUI → Tools
3. **[Testar o fluxo de alerta](docs/04-testes.md)** — do problema ao WhatsApp

O **[Grafana](docs/05-grafana.md)** já sobe pronto: datasource do Zabbix
provisionado, é só abrir http://localhost:3002 e montar dashboards.

## Portas

| Porta | Serviço |
|---|---|
| 8080 | Zabbix web (`Admin` / `zabbix`) |
| 8081 | MCP endpoint (`/mcp`, `/health`) |
| 9091 | MCP admin portal |
| 3000 | WA-AKG dashboard + API (`/docs` = Swagger) |
| 3001 | Open WebUI |
| 3002 | Grafana (`admin` / senha no `.env` → `GRAFANA_ADMIN_PASSWORD`) |
| 8001 | Laya via mcpo (`/docs` = OpenAPI) |
| 11434 | Ollama |
| 10051 | Zabbix server (trapper) |

## Estrutura

```
├── docker-compose.yml        # stack completo
├── .env                      # segredos (gerado pelo bootstrap)
├── config/
│   ├── credenciais.txt       # todas as credenciais (chmod 600)
│   ├── grafana/provisioning/ # datasource Zabbix + dashboards (auto)
│   └── zabbix-mcp/config.toml
├── laya/                     # JEV/Laya: Dockerfile + binário + modelo GGUF
├── repos/                    # clones: zabbix-mcp-server, WA-AKG, laya_mcp
├── scripts/
│   ├── bootstrap.sh          # provisionamento 1-comando
│   └── zabbix_bootstrap.py   # automação da API do Zabbix
└── docs/                     # guias passo a passo
```

## Comandos úteis

```bash
docker compose ps                     # status
docker compose logs -f zabbix-server  # logs de um serviço
docker compose restart zabbix-mcp     # após editar config.toml
docker exec zlab-ollama ollama list   # modelos baixados
docker compose down                   # parar tudo
docker compose down -v                # parar e APAGAR todos os dados
```

## ⚠️ Avisos

- **WhatsApp**: o pareamento usa seu número pessoal via protocolo WhatsApp Web
  (Baileys). Automação carrega risco (baixo, mas real) de banimento. Para
  produção, use um chip dedicado.
- **Credenciais padrão do Zabbix** (`Admin`/`zabbix`): troque após o 1º login.
- **Laya em CPU**: decisões zero-shot genéricas ficam perto do acaso; os
  presets (`laya_gate`, `laya_triage`) são os casos confiáveis. Trate as
  probabilidades como **advisory**, nunca como gate absoluto.
- **RAM**: o stack todo consome ~8–10 GB com o modelo 8B carregado. Se ficar
  apertado, troque `OLLAMA_MODEL` para `llama3.2:3b` no `.env`.

## Troubleshooting (compatibilidade de versões)

Correções aplicadas durante o setup — se atualizar os repositórios
(`git pull` em `repos/`) e algo quebrar, olhe aqui primeiro:

| Sintoma | Causa | Onde está a correção |
|---|---|---|
| `mcpo` não sobe (`ImportError`) | `mcp` 2.x renomeou APIs que o `mcpo` 0.0.20 usa | `laya/Dockerfile` (sed de compat.) |
| `laya daemon closed stdout` | falta `libgomp.so.1` no container | `laya/Dockerfile` (`libgomp1`) |
| `mediatype.create: exec_path is missing` | no Zabbix 7.0 webhook é `type: 4`, não `1` | `scripts/zabbix_bootstrap.py` |
| `token.generate: Invalid params` | API 7.0.31 quer `tokenids` escalar | `scripts/zabbix_bootstrap.py` |

Comandos de diagnóstico:

```bash
docker compose ps                       # status geral
docker logs zlab-laya --tail 30         # Laya/mcpo
docker logs zlab-mcp --tail 30          # MCP server
docker exec zlab-laya python /app/laya_mcp_server.py --check   # engine Laya
curl http://localhost:8081/health       # MCP health
curl http://localhost:8001/openapi.json # Laya tools
```

## Reconstruir do zero

```bash
docker compose down -v                  # apaga TODOS os dados
rm -f config/zabbix-mcp/config.toml config/credenciais.txt
./scripts/bootstrap.sh
```
