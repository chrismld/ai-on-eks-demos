#!/bin/bash

set -xeuo pipefail

force=false

if [[ "${1:-}" == "--force" ]]; then
  force=true
fi

if [[ "$force" == true ]]; then
  rm -rf images/*
fi

function render {
  local output_file=$1
  local panel_id=panel-$2
  if [[ "$force" == false && -f images/${panel_id}_${output_file} ]]; then
    echo "Skipping existing image: images/${panel_id}_${output_file}"
    return
  fi
  curl -sS -u admin:admin -o images/${panel_id}_${output_file} "http://localhost:3000/render/d-solo/presentation/autoscaling-lag?orgId=1&from=2026-01-27T10:10:50.000Z&to=2026-01-27T11:03:45.000Z&panelId=${panel_id}&width=1024&height=384&scale=2&tz=UTC"
}

render spike_rps.png 1
render spike_rps+mem.png 2
render spike_rps+mem+pods.png 3
render spike_rps+pods.png 4
render spike_rps+pods_prom.png 5
render spike_rps+pods_otel.png 6
render spike_rps+predictive.png 7
render spike_rps+predictive+otel.png 8
render spike_rps+prom_overload.png 9
