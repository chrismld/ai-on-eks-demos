#!/usr/bin/env bash

set -xeuo pipefail

docker-compose -f grafana-inline/docker-compose.yml down
docker-compose -f grafana-inline/docker-compose.yml up -d --force-recreate
