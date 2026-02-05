# Autoscaling Lag Demo (Grafana + Inline CSV)

This contains grafana dashboards for a talk / presentation: it spins up Grafana locally, provisions a dashboard, and lets you render **PNG exports** for slides.

The dashboard(s) use the **Infinity datasource** with **Inline CSV** targets so you can iterate quickly on "what the chart should look like" without standing up Prometheus.

---

## What's in here

- `setup_local_grafana.sh` – creates a minimal `grafana-inline/` Docker Compose project with provisioning + a starter dashboard.
- `gen_memory_csv.py` – generates realistic, spiky "container memory" time series data (1h by default).
- `sync_values.sh` – copies CSV files from `./data/` into the provisioned dashboard JSON (Inline CSV strings).
- `render.sh` – renders a set of panel images via Grafana's `/render/...` endpoint (great for slide decks).
- `restart.sh` – restarts the local Grafana stack.
- `logs.sh` – tails Grafana logs.
- `data/` – put your CSVs here (see below).
- `images/` – rendered output images end up here.

---

## Prerequisites

- Docker
- Docker Compose v2 (`docker compose …`)
- `curl`
- `jq` (used by `sync_values.sh`)
- Python 3 (only needed if you use `gen_memory_csv.py`)

---

## Quick start

```bash
chmod +x setup_local_grafana.sh
./setup_local_grafana.sh
```

Open Grafana:

- http://localhost:3000  
- login: `admin / admin` (or overridden via env vars)

---

## Working with data

This project expects CSV files in `./data/`. The default "shape" used throughout is:

```csv
time,value
2026-01-27T10:10:50Z,123
2026-01-27T10:10:55Z,127
...
```

### Generate realistic memory data (spiky, short sampling)

```bash
mkdir -p data
python3 gen_memory_csv.py --seed 7 --step 5 --seconds 3600 > data/memory-usage.csv
```

Tune realism with:
- `--step` (sampling period; smaller = more "stock-chart jagged")
- `--small_p` / `--big_p` (spike frequency)

### Sync CSV → dashboard Inline CSV strings

`sync_values.sh` reads CSV files and injects them into the inline targets inside:

```
grafana-inline/grafana/dashboards/demo-inline.json
```

Expected filenames (adjust in the script if you rename):
- `data/memory-usage.csv`
- `data/number-of-pods-better-miss.csv`
- `data/rps-miss.csv`

Run:

```bash
chmod +x sync_values.sh
./sync_values.sh
```

Then refresh Grafana (or restart Grafana if your provisioning doesn't poll).

---

## Rendering images for slides

If you've set up the Grafana Image Renderer (or your Grafana supports `/render`), you can export panels as high-resolution PNG.

```bash
chmod +x render.sh
./render.sh --force
```

Rendered files go to `./images/`.

### Notes about `render.sh`

- It uses basic auth (`-u admin:admin`). If you enable anonymous access, you can remove `-u …`.
- It renders via a URL like:

```
/render/d-solo/<uid>/<slug>?panelId=<id>&from=...&to=...&width=...&height=...&scale=...
```

If your dashboard UID/slug or panel IDs differ, update `render.sh`.

**For sharper output**, increase:
- `width` (e.g., 3200–4000)
- `height` (e.g., 1600–2200)
- `scale` (2–3)

---

## Handy commands

Restart:

```bash
chmod +x restart.sh
./restart.sh
```

Tail logs:

```bash
chmod +x logs.sh
./logs.sh
```
