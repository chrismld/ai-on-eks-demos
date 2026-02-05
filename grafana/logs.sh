#!/usr/bin/env bash

set -xeuo pipefail

docker compose -f grafana-inline/docker-compose.yml logs --tail=80 grafana
