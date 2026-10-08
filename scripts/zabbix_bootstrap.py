#!/usr/bin/env python3
# ==============================================================================
# zabbix_bootstrap.py — provisiona o Zabbix do lab via API:
#   1. Aguarda a API do Zabbix responder
#   2. Login Admin/zabbix (credenciais padrão do container)
#   3. Cria API token "zabbix-mcp" e grava no config.toml do MCP server
#   4. Cria o media type "WhatsApp" (webhook → WA-AKG)
#   5. Cadastra o host demo "zabbix-agent-docker"
#
# Uso: python3 zabbix_bootstrap.py --zbx-url http://localhost:8080 \
#          --config ../config/zabbix-mcp/config.toml --wa-api-key <key>
# Somente stdlib. Idempotente.
# ==============================================================================
import argparse
import json
import sys
import time
import urllib.request
import urllib.error

WEBHOOK_JS = r"""
try {
  var params = JSON.parse(value);

  if (!params.SESSION_ID || params.SESSION_ID === 'PREENCHER') {
    throw 'SESSION_ID nao configurado. Crie a sessao no dashboard WA-AKG ' +
          '(http://localhost:3000), pareie o WhatsApp e atualize este media type.';
  }

  var url = params.URL.replace(/\/+$/, '') +
            '/api/messages/' + encodeURIComponent(params.SESSION_ID) +
            '/' + encodeURIComponent(params.TO) + '/send';

  var payload = JSON.stringify({
    message: { text: '*' + params.SUBJECT + '*\n\n' + params.MESSAGE }
  });

  var req = new HttpRequest();
  req.addHeader('Content-Type: application/json');
  req.addHeader('X-API-Key: ' + params.API_KEY);

  var resp = req.post(url, payload);
  var code = req.getStatus();

  if (code < 200 || code >= 300) {
    throw 'WA-AKG respondeu HTTP ' + code + ': ' + resp;
  }
  return 'OK';
} catch (e) {
  Zabbix.Log(3, '[WhatsApp webhook] ' + e);
  throw 'Falha no envio WhatsApp: ' + e;
}
""".strip()


def api(url, method, params, auth=None, req_id=1):
    body = {"jsonrpc": "2.0", "method": method, "params": params, "id": req_id}
    if auth:
        body["auth"] = auth
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{url}/api_jsonrpc.php", data=data,
        headers={"Content-Type": "application/json-rpc"})
    with urllib.request.urlopen(req, timeout=30) as r:
        out = json.loads(r.read())
    if "error" in out:
        raise RuntimeError(f"{method}: {out['error']}")
    return out["result"]


def wait_api(url, timeout_s=420):
    print(f"[*] Aguardando API do Zabbix em {url} ...")
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        try:
            v = api(url, "apiinfo.version", {})
            print(f"[OK] Zabbix API online — versão {v}")
            return v
        except Exception:
            time.sleep(5)
    raise SystemExit("[ERRO] API do Zabbix não respondeu a tempo.")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--zbx-url", default="http://localhost:8080")
    p.add_argument("--zbx-user", default="Admin")
    p.add_argument("--zbx-pass", default="zabbix")
    p.add_argument("--config", required=True, help="config.toml do zabbix-mcp")
    p.add_argument("--wa-api-key", required=True, help="API key do WA-AKG")
    p.add_argument("--wa-url", default="http://wa-akg:3000")
    args = p.parse_args()

    wait_api(args.zbx_url)

    print(f"[*] Login como {args.zbx_user} ...")
    auth = api(args.zbx_url, "user.login",
               {"username": args.zbx_user, "password": args.zbx_pass})
    print("[OK] Login efetuado")

    # ------------------------------------------------------------ API token
    existing = api(args.zbx_url, "token.get",
                   {"output": ["tokenid", "name"]}, auth)
    tok = next((t for t in existing if t["name"] == "zabbix-mcp"), None)
    if tok:
        api(args.zbx_url, "token.delete", [tok["tokenid"]], auth)
        print("[*] Token antigo 'zabbix-mcp' removido")
    tid = api(args.zbx_url, "token.create",
              {"name": "zabbix-mcp", "userid": "2"}, auth)["tokenids"][0]
    # token.generate no 7.0.31 quer tokenids escalar (int), não array
    token_str = api(args.zbx_url, "token.generate",
                    {"tokenids": int(tid)}, auth)[0]["token"]
    print(f"[OK] API token criado (tokenid={tid})")

    with open(args.config, "r", encoding="utf-8") as f:
        cfg = f.read()
    if "__ZABBIX_API_TOKEN__" not in cfg:
        print("[AVISO] config.toml não tem placeholder; token não gravado")
    else:
        with open(args.config, "w", encoding="utf-8") as f:
            f.write(cfg.replace("__ZABBIX_API_TOKEN__", token_str))
        print(f"[OK] Token gravado em {args.config}")

    # ------------------------------------------------------- Media type WA
    mt = api(args.zbx_url, "mediatype.get",
             {"filter": {"name": "WhatsApp"}}, auth)
    mt_params = [
        {"name": "URL", "value": args.wa_url},
        {"name": "SESSION_ID", "value": "PREENCHER"},
        {"name": "API_KEY", "value": args.wa_api_key},
        {"name": "TO", "value": "{ALERT.SENDTO}"},
        {"name": "SUBJECT", "value": "{ALERT.SUBJECT}"},
        {"name": "MESSAGE", "value": "{ALERT.MESSAGE}"},
    ]
    templates = [
        {"eventsource": "0", "recovery": "0",
         "subject": "PROBLEMA: {EVENT.NAME}",
         "message": "🚨 *{EVENT.SEVERITY}* — {EVENT.NAME}\n"
                    "Host: {HOST.NAME}\nItem: {ITEM.NAME}\n"
                    "Valor: {ITEM.VALUE}\nData: {EVENT.DATE} {EVENT.TIME}"},
        {"eventsource": "0", "recovery": "1",
         "subject": "RESOLVIDO: {EVENT.NAME}",
         "message": "✅ {EVENT.NAME}\nHost: {HOST.NAME}\n"
                    "Duração: {EVENT.AGE}\nData: {EVENT.RECOVERY.DATE} "
                    "{EVENT.RECOVERY.TIME}"},
        {"eventsource": "0", "recovery": "2",
         "subject": "ATUALIZAÇÃO: {EVENT.NAME}",
         "message": "ℹ️ {EVENT.NAME}\nHost: {HOST.NAME}\n{USER.FULLNAME}: "
                    "{EVENT.UPDATE.MESSAGE}"},
    ]
    if mt:
        api(args.zbx_url, "mediatype.update",
            {"mediatypeid": mt[0]["mediatypeid"], "script": WEBHOOK_JS,
             "parameters": mt_params}, auth)
        print("[OK] Media type 'WhatsApp' atualizado")
    else:
        # type=4 é webhook no Zabbix 7.0 (1 = script, que exige exec_path)
        api(args.zbx_url, "mediatype.create", {
            "name": "WhatsApp",
            "type": 4,
            "script": WEBHOOK_JS,
            "timeout": "30s",
            "parameters": mt_params,
            "message_templates": templates,
            "description": "Alertas via WA-AKG (gateway WhatsApp self-hosted). "
                           "Configure SESSION_ID após parear o WhatsApp.",
        }, auth)
        print("[OK] Media type 'WhatsApp' criado")

    # ------------------------------------------------------------ Host demo
    hosts = api(args.zbx_url, "host.get",
                {"filter": {"host": ["zabbix-agent-docker"]}}, auth)
    if hosts:
        print("[OK] Host 'zabbix-agent-docker' já existe")
    else:
        gid = api(args.zbx_url, "hostgroup.get",
                  {"filter": {"name": ["Linux servers"]}}, auth)[0]["groupid"]
        tid2 = api(args.zbx_url, "template.get",
                   {"filter": {"host": ["Linux by Zabbix agent"]}},
                   auth)[0]["templateid"]
        api(args.zbx_url, "host.create", {
            "host": "zabbix-agent-docker",
            "name": "Zabbix Agent (Docker Lab)",
            "groups": [{"groupid": gid}],
            "templates": [{"templateid": tid2}],
            "interfaces": [{"type": "1", "main": "1", "useip": "0",
                            "ip": "", "dns": "zabbix-agent",
                            "port": "10050"}],
        }, auth)
        print("[OK] Host 'zabbix-agent-docker' criado (template Linux by Zabbix agent)")

    print("\n[CONCLUÍDO] Zabbix provisionado.")


if __name__ == "__main__":
    sys.exit(main())
