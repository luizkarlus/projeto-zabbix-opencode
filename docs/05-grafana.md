# 05 — Grafana

## Acesso

**http://localhost:3002** — usuário `admin`, senha em `GRAFANA_ADMIN_PASSWORD`
no `.env` (também em `config/credenciais.txt`).

## O que já vem pronto

- **Plugin Zabbix** (`alexanderzobnin-zabbix-app`) instalado via
  `GF_INSTALL_PLUGINS` no compose.
- **Datasource "Zabbix"** provisionado e marcado como default
  (`config/grafana/provisioning/datasources/zabbix.yml`), apontando para a API
  do `zabbix-web` com `trends` habilitado.
- **Provider de dashboards** lendo JSONs de `/var/lib/grafana/dashboards`
  (pasta *Zabbix Lab* na UI).

> O datasource usa as credenciais padrão do Zabbix (`Admin`/`zabbix`).
> Se trocar a senha do Admin, edite o arquivo acima e
> `docker compose restart grafana`.

## Primeiro dashboard

1. **Dashboards → New → New dashboard → Add visualization** → datasource
   *Zabbix*.
2. Em Query: Group `Linux servers` → Host `Zabbix Agent (Docker Lab)` →
   Item (ex.: `CPU utilization`, `Memory utilization`).
3. Sugestões de painéis para o lab:
   - **CPU/Memória/Disco** do agent demo (time series)
   - **Problemas ativos**: query mode *Problems*, agrupado por severidade
   - **Gauge de disponibilidade** do agent (`Agent ping`)

## Dica: IA ajudando no dashboard

Com o MCP conectado (ver [03-openwebui.md](03-openwebui.md)), você pode pedir
no chat:

```
Quais são os 5 itens mais interessantes do host Zabbix Agent (Docker Lab)
para um dashboard de capacidade? Me dê os nomes exatos dos itens e keys.
```

E usar os nomes diretamente nas queries do Grafana.

## Importar dashboards prontos

**Dashboards → New → Import** — cole um ID do
[Grafana.com/dashboards](https://grafana.com/grafana/dashboards/) filtrando
por "Zabbix" (ex.: dashboards para o plugin alexanderzobnin). Verifique se o
dashboard pede a datasource *Zabbix* na importação.
