#!/usr/bin/env bash
set -euo pipefail

# Grafana + Infinity (Inline CSV) "no-click" setup.
# Creates a local docker-compose project with provisioning + a demo dashboard.
#
# Requirements:
#   - Docker installed
#   - Docker Compose v2 available as: docker compose
#
# Usage:
#   chmod +x grafana_inline_setup.sh
#   ./grafana_inline_setup.sh
#
# Then open:
#   http://localhost:3000  (admin/admin by default)

PROJECT_DIR="${PROJECT_DIR:-grafana-inline}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"

INFINITY_PLUGIN="${INFINITY_PLUGIN:-yesoreyeram-infinity-datasource}"

if [ -d "${PROJECT_DIR}" ]; then
  echo "Error: Project directory already exists: ${PROJECT_DIR}"
  echo "Please remove or choose a different PROJECT_DIR."
  exit 1
fi

echo "==> Creating project at: ${PROJECT_DIR}"
mkdir -p "${PROJECT_DIR}/grafana/provisioning/datasources"
mkdir -p "${PROJECT_DIR}/grafana/provisioning/dashboards"
mkdir -p "${PROJECT_DIR}/grafana/dashboards"

cat > "${PROJECT_DIR}/docker-compose.yml" <<YAML
services:
  grafana:
    image: grafana/grafana:latest
    ports:
      - "${GRAFANA_PORT}:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - GF_USERS_DEFAULT_THEME=dark
      # Plugin install (most common)
      - GF_INSTALL_PLUGINS=${INFINITY_PLUGIN}
      # If your image ignores GF_INSTALL_PLUGINS, comment the line above and try:
      # - GF_PLUGINS_PREINSTALL_SYNC=${INFINITY_PLUGIN}
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
YAML

cat > "${PROJECT_DIR}/grafana/provisioning/datasources/infinity.yaml" <<YAML
apiVersion: 1

datasources:
  - name: Infinity
    type: yesoreyeram-infinity-datasource
    access: proxy
    uid: infinity
    isDefault: false
    editable: false
    jsonData:
      datasource_mode: basic
YAML

cat > "${PROJECT_DIR}/grafana/provisioning/dashboards/dashboards.yaml" <<YAML
apiVersion: 1

providers:
  - name: "local"
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    editable: false
    options:
      path: /var/lib/grafana/dashboards
YAML

# Demo dashboard using Infinity Inline CSV.
# NOTE: You can regenerate/replace the "data" field below with any CSV content you want.
cat > "${PROJECT_DIR}/grafana/dashboards/demo-inline.json" <<'JSON'
{
  "uid": "demo_inline",
  "title": "Demo - Infinity Inline",
  "schemaVersion": 36,
  "version": 1,
  "time": { "from": "now-15m", "to": "now" },
  "panels": [
    {
      "id": 1,
      "type": "timeseries",
      "title": "Inline CSV (Infinity)",
      "gridPos": { "h": 10, "w": 24, "x": 0, "y": 0 },
      "datasource": { "type": "yesoreyeram-infinity-datasource", "uid": "infinity" },
      "targets": [
        {
          "refId": "A",
          "datasource": { "type": "yesoreyeram-infinity-datasource", "uid": "infinity" },
          "type": "csv",
          "source": "inline",
          "format": "timeseries",
          "global_query_id": "",
          "data": "time,value\n2026-01-27T12:00:00Z,10\n2026-01-27T12:01:00Z,12\n2026-01-27T12:02:00Z,8\n2026-01-27T12:03:00Z,15\n",
          "columns": [
            { "selector": "time", "text": "time", "type": "string" },
            { "selector": "value", "text": "value", "type": "number" }
          ],
          "filters": [],
          "root_selector": "",
          "url": "",
          "url_options": { "method": "GET", "data": "" }
        }
      ],
      "options": {
        "legend": { "showLegend": true, "displayMode": "list", "placement": "bottom" }
      }
    }
  ]
}
JSON

echo "==> Starting Grafana (this may take a moment on first run)..."
(
  cd "${PROJECT_DIR}"
  docker compose up -d
)

echo
echo "==> Done."
echo "Open: http://localhost:${GRAFANA_PORT}"
echo "Login: ${ADMIN_USER} / ${ADMIN_PASSWORD}"
echo
echo "Tip: To change the inline CSV later, edit:"
echo "  ${PROJECT_DIR}/grafana/dashboards/demo-inline.json"
echo "Then restart Grafana:"
echo "  (cd ${PROJECT_DIR} && docker compose restart grafana)"

