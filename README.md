# n8n — Automatización IT (Wazuh + AD 2019 + Exchange 2019)

Repositorio de flujos n8n y reglas Wazuh para automatizar operaciones de IT en
un entorno Windows (AD 2019 + Exchange 2019) con SIEM Wazuh. Entorno de
laboratorio — valores de ejemplo usan `empresa.local`.

## Arquitectura

```
 ┌──────────┐   ┌──────────┐   ┌──────────────┐
 │  Wazuh   │──▶│          │──▶│   Exchange   │  (alertas por email)
 │  (SIEM)  │   │          │   └──────────────┘
 └──────────┘   │   n8n    │   ┌──────────────┐
 ┌──────────┐   │ (orch.)  │──▶│ Ticket / API │  (acciones)
 │  AD 2019 │──▶│          │   └──────────────┘
 └──────────┘   └──────────┘
                     │
                     ▼
              ┌──────────────┐
              │  Postgres    │  (auditoría / snapshots)
              └──────────────┘
```

- n8n: `http://172.16.30.9:5678`
- Wazuh: `https://172.16.30.8`

## Flujos incluidos

| # | Archivo | Trigger | Qué hace |
|---|---|---|---|
| 1 | `n8n/workflows/01-ping-vm-monitor.json` | Cron 5m | Ping a VMs críticas; email si falla |
| 2 | `n8n/workflows/02-ad-new-users.json` | Cron 10m | Detecta cuentas AD nuevas (últimos 10 días) y notifica |
| 3 | `n8n/workflows/03-privilege-escalation.json` | Cron 15m | Compara membresía de grupos admin vs snapshot previo |
| 4 | `n8n/workflows/04-software-install-detection.json` | Webhook Wazuh | Valida instalaciones contra whitelist + VirusTotal |
| 5 | `n8n/workflows/05-suspicious-downloads.json` | Webhook Wazuh FIM | Hash SHA256 + VirusTotal de descargas ejecutables |

Backlog (10 ideas adicionales) en `n8n/flujos_n8n.json` → `ideas_adicionales`.

## Quickstart

### 1. Preparar credenciales en la UI de n8n
Abrir `http://172.16.30.9:5678` y crear credenciales con estos nombres exactos:

| Nombre | Tipo | Para |
|---|---|---|
| `wazuh-api` | HTTP Header Auth | API Wazuh (55000) |
| `ad-winrm` | SSH / WinRM | Ejecutar PowerShell en DC |
| `exchange-smtp` | SMTP | Envío de emails |
| `virustotal` | HTTP Header Auth (`x-apikey`) | VirusTotal API |
| `postgres-n8n` | Postgres | Auditoría |

### 2. Generar API key de n8n
`http://172.16.30.9:5678/settings/api` → Create API key → copiar.

### 3. Importar workflows
```bash
cp .env.example .env        # editar con tu API key
source .env
./scripts/deploy-n8n-workflows.sh
```

### 4. Desplegar reglas Wazuh
```bash
WAZUH_HOST=172.16.30.8 WAZUH_SSH_USER=root ./scripts/deploy-wazuh-rules.sh
```

### 5. Activar los workflows
En la UI de n8n, abrir cada workflow importado y pulsar el toggle "Active".
Los de tipo webhook (4 y 5) te darán la URL a configurar como `integrator`
en Wazuh.

## Estructura

```
.
├── docker-compose.yml           # referencia (n8n + postgres)
├── .env.example
├── docs/                        # guía detallada
├── Automatizacion_IT_n8n_Wazuh_AD_Exchange.docx  # documento fuente (en raíz)
├── n8n/
│   ├── workflows/               # 5 JSONs importables
│   └── flujos_n8n.json          # descripción conceptual original
├── wazuh/rules/local_rules.xml  # 4 reglas (100200/01, 100300/01)
├── ad/powershell/               # scripts para nodo Execute Command
└── scripts/                     # deploy n8n + wazuh
```

## Documentación detallada

Ver [`docs/GUIA_RAPIDA_CONFIGURACION.md`](docs/GUIA_RAPIDA_CONFIGURACION.md)
para preparación de cuenta de servicio en AD, mailbox en Exchange, firewall,
backups y troubleshooting.
