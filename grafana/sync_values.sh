#!/bin/bash
# cat grafana-inline/grafana/dashboards/memory-usage.csv
# put into grafana-inline/grafana/dashboards/demo-inline.json under field panels[0].targets[0].data
set -xeuo pipefail

JSON_FILE="grafana-inline/grafana/dashboards/demo-inline.json"

# Read CSV content and escape double quotes
memory=$(cat data/memory-usage.csv | sed 's/"/\\"/g')
pods=$(cat data/number-of-pods-better-miss.csv | sed 's/"/\\"/g')
rps=$(cat data/rps-miss.csv | sed 's/"/\\"/g')

# Update the JSON file using jq
jq --arg data "$memory" ".panels[0].targets[0].data = \$data" "$JSON_FILE" > tmp.$$.json && mv tmp.$$.json "$JSON_FILE"
jq --arg data "$pods" ".panels[0].targets[1].data = \$data" "$JSON_FILE" > tmp.$$.json && mv tmp.$$.json "$JSON_FILE"
jq --arg data "$rps" ".panels[0].targets[2].data = \$data" "$JSON_FILE" > tmp.$$.json && mv tmp.$$.json "$JSON_FILE"
