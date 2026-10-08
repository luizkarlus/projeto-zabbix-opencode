# 02 — WhatsApp: pareamento e integração com o Zabbix

## 1. Criar a sessão no WA-AKG

1. Abra **http://localhost:3000** e faça login com as credenciais de
   `config/credenciais.txt` (WA-AKG).
2. Vá em **Sessions → New Session**, dê um nome (ex.: `zabbix-alerts`).
3. Clique na sessão → **QR Code** e escaneie com o WhatsApp
   (*Aparelhos conectados → Conectar aparelho*).
4. Aguarde o status ficar **connected/online**.

> A sessão persiste no volume Docker — só precisa parear de novo se o
> WhatsApp desconectar o aparelho.

## 2. Descobrir o SESSION_ID

- No dashboard, o card da sessão mostra o ID (ex.: `xgj7d9`), **ou**
- Via API:

```bash
API_KEY=$(grep 'API key' config/credenciais.txt | awk '{print $NF}')
curl -s -H "X-API-Key: $API_KEY" http://localhost:3000/api/sessions | python3 -m json.tool
```

## 3. Configurar o media type no Zabbix

O bootstrap já criou **Alertas → Media types → WhatsApp**. Falta só:

1. Abra o media type **WhatsApp**.
2. No parâmetro `SESSION_ID`, troque `PREENCHER` pelo ID da sessão.
3. Salve.

Parâmetros (já preenchidos):

| Parâmetro | Valor |
|---|---|
| `URL` | `http://wa-akg:3000` (rede interna do Docker) |
| `API_KEY` | gerada no bootstrap |
| `TO` | `{ALERT.SENDTO}` |
| `SUBJECT` / `MESSAGE` | macros de alerta |

## 4. Ligar o media type ao usuário Admin

1. **Users → Users → Admin → aba Media → Add**
2. Type: `WhatsApp` · **Send to**: seu número no formato JID:
   `55DDNNNNNNNNN@s.whatsapp.net` (ex.: `5511987654321@s.whatsapp.net`)
3. Add → Update.

> Dica: para receber em **grupo**, adicione o número do "bot" ao grupo e use
> o JID do grupo (`...@g.us`). O JID aparece nos logs/webhooks do WA-AKG.

## 5. Criar a Action de alerta

1. **Alerts → Actions → Trigger actions → Create action**
2. Nome: `WhatsApp alerts`
3. Condição (opcional): severidade ≥ *Average*
4. **Operations → Add**: enviar para usuário `Admin`, media `WhatsApp`
5. **Recovery operations**: mesma coisa (para receber o "RESOLVIDO ✅")
6. Add.

## 6. Testar

Caminho rápido (sem precisar de problema real):

**Alertas → Media types → WhatsApp → Test** e preencha:

| Campo | Valor |
|---|---|
| `TO` | `55DDNNNNNNNNN@s.whatsapp.net` |
| `SUBJECT` | `Teste Zabbix` |
| `MESSAGE` | `Pipeline OK 🚀` |

Deve retornar `OK` e a mensagem chegar no seu WhatsApp.

O teste completo (problema real → action → WhatsApp) está em
[04-testes.md](04-testes.md).
