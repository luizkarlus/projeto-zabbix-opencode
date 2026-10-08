# 04 — Testes de ponta a ponta

## 1. Teste rápido do pipeline WhatsApp

**Alertas → Media types → WhatsApp → Test** (ver [02-whatsapp.md](02-whatsapp.md#6-testar)).

## 2. Alerta real: derrube o agent demo

O host `zabbix-agent-docker` é monitorado com o template
*Linux by Zabbix agent*, que dispara problema se o agent ficar indisponível.

```bash
# "Derruba" o agent → em ~1-2 min dispara o problema
docker stop zlab-agent

# Acompanhe em Monitoring → Problems
# Você deve receber o WhatsApp: 🚨 PROBLEMA ...

# "Recupera"
docker start zlab-agent
# Você deve receber: ✅ RESOLVIDO ...
```

## 3. Alerta de carga: stress no agent

```bash
# Sobe a carga do container do agent (usa 1 core por 5 min)
docker exec -d zlab-agent sh -c \
  "yes > /dev/null & SPID=\$!; sleep 300; kill \$SPID"
```

O trigger de CPU do template deve disparar (se necessário, ajuste o limiar
ou rode mais workers: `yes > /dev/null & yes > /dev/null &`).

## 4. Validar a IA (Open WebUI)

```
Me mostre o resumo de saúde da infraestrutura monitorada
```

```
Há algum problema ativo? Classifique a severidade com laya_decide
e me explique com os dados do Zabbix.
```

```
Passe o texto do último alerta pelo laya_gate antes de resumir.
```

## 5. Validar o Laya isoladamente

```bash
curl -s http://localhost:8001/openapi.json | python3 -c \
  "import json,sys; print(list(json.load(sys.stdin)['paths']))"

curl -s -X POST http://localhost:8001/laya_health | python3 -m json.tool

curl -s -X POST http://localhost:8001/laya_triage \
  -H 'Content-Type: application/json' \
  -d '{"text": "Servidor de produção fora do ar desde 03h, clientes ligando"}' \
  | python3 -m json.tool
```

## 6. Validar o MCP do Zabbix isoladamente

```bash
TOKEN=$(grep 'Bearer token' config/credenciais.txt | awk '{print $NF}')

curl -s http://localhost:8081/health

curl -s -X POST http://localhost:8081/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | head -c 600
```

## 7. Checagem geral

```bash
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
```
