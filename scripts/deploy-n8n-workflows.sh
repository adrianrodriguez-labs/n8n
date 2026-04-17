#!/usr/bin/env bash
# Importa todos los workflows en n8n/workflows/ a la instancia n8n.
#
# Requiere:
#   N8N_URL      (ej: http://172.16.30.9:5678)
#   N8N_API_KEY  (generar en $N8N_URL/settings/api)
#
# Uso:
#   source .env && ./scripts/deploy-n8n-workflows.sh
#   # o
#   N8N_URL=... N8N_API_KEY=... ./scripts/deploy-n8n-workflows.sh

set -euo pipefail

: "${N8N_URL:?Falta N8N_URL}"
: "${N8N_API_KEY:?Falta N8N_API_KEY}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$SCRIPT_DIR/../n8n/workflows"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq no esta instalado" >&2
  exit 1
fi

echo "Importando workflows desde $WORKFLOWS_DIR a $N8N_URL"

for f in "$WORKFLOWS_DIR"/*.json; do
  name="$(jq -r '.name' "$f")"
  echo "-> $name ($f)"
  response="$(curl -fsS -X POST "$N8N_URL/api/v1/workflows" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary "@$f")"
  echo "   id=$(echo "$response" | jq -r '.id')"
done

echo "Listo. Activa los workflows manualmente en la UI si lo deseas."
