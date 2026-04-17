#!/usr/bin/env bash
# Copia wazuh/rules/local_rules.xml al Wazuh manager y reinicia el servicio.
#
# Requiere:
#   WAZUH_HOST      (ej: 172.16.30.8)
#   WAZUH_SSH_USER  (default: root)
#
# Uso:
#   WAZUH_HOST=172.16.30.8 WAZUH_SSH_USER=root ./scripts/deploy-wazuh-rules.sh
#
# Nota: si Wazuh corre en Docker, ajusta RESTART_CMD para usar
# `docker exec wazuh-manager ...` en lugar de ejecutar directo en el host.

set -euo pipefail

: "${WAZUH_HOST:?Falta WAZUH_HOST}"
WAZUH_SSH_USER="${WAZUH_SSH_USER:-root}"
REMOTE_PATH="${REMOTE_PATH:-/var/ossec/etc/rules/local_rules.xml}"
RESTART_CMD="${RESTART_CMD:-/var/ossec/bin/wazuh-control restart}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/../wazuh/rules/local_rules.xml"

if [ ! -f "$SRC" ]; then
  echo "Error: no existe $SRC" >&2
  exit 1
fi

echo "Copiando $SRC a $WAZUH_SSH_USER@$WAZUH_HOST:$REMOTE_PATH"
scp "$SRC" "$WAZUH_SSH_USER@$WAZUH_HOST:$REMOTE_PATH"

echo "Ajustando permisos y reiniciando wazuh-manager"
ssh "$WAZUH_SSH_USER@$WAZUH_HOST" "chown wazuh:wazuh $REMOTE_PATH && chmod 0640 $REMOTE_PATH && $RESTART_CMD"

echo "Listo. Verifica en /var/ossec/logs/ossec.log que no haya errores de parseo."
