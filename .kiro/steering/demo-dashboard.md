---
inclusion: fileMatch
fileMatchPattern: "**/demo-dashboard.sh"
---

# Demo Dashboard Layout Rules

When modifying `scripts/dashboard/demo-dashboard.sh`, follow these strict layout constraints:

# Terminal/Shell Usage

- IMPORTANT! Do NOT paste or insert more than 5 lines of text into the terminal. Instead, write to temporary files in ./kiro-temp and clean up files after usage.

## Terminal Width Constraints

- **Most sections**: 80 characters max per line
- **vLLM Pods section (render_pods_section)**: 82 characters max per line (exception for visual alignment)
- **Performance section**: 80 characters exactly

## Section-Specific Padding Values

### vLLM Pods Section (`render_pods_section`)
The "Ready" line has different padding based on state:

**With pending pods:**
- With startup display: `printf "%*s" "$((1 - stale_padding))" ""`
- Without startup display: `printf "%*s" "$((19 - stale_padding))" ""`

**Without pending pods:**
- With startup display: `printf "%*s" "$((21 - stale_padding))" ""`
- Without startup display: `printf "%*s" "$((39 - stale_padding))" ""` ← This is the key value!

### Performance Section (`render_performance_section`)
- Field widths: `%-5s` for Avg, p50, p95, p99 latency values
- Final padding before border: `$((3 - stale_padding))`

### Scaling Metrics Section (`render_queue_section`)
Shows vLLM waiting and running requests with two separate visual bars.

**Current layout (80 chars per line):**
```
┌─ Scaling Metrics (vLLM # of requests) ───────────────────────────────────────┐
│ Waiting: 5    | Target: 1             Running: 3    | Target: 5              │
│ [███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]  [██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░] │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Key values:**
- Header: 39 dashes after title text
- Waiting bar width: 34 characters
- Running bar width: 36 characters
- Padding before right border on metrics line: `$((13 - stale_padding))`
- Gap between bars: 2 spaces `]  [`

## Testing Commands

### Run all tests
```bash
bats scripts/tests/demo-dashboard.bats
```

### Verify line lengths for a specific section
Use this pattern to check actual character counts (strips ANSI color codes):

**Queue/Scaling section:**
```bash
source scripts/dashboard/demo-dashboard.sh 2>/dev/null; METRIC_QUEUE_DEPTH=5; METRIC_RUNNING_REQUESTS=3; render_queue_section | while IFS= read -r line; do stripped=$(echo "$line" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'); echo "len=${#stripped}: $stripped"; done
```

**Pods section:**
```bash
source scripts/dashboard/demo-dashboard.sh 2>/dev/null; METRIC_PODS_RUNNING=3; METRIC_PODS_DESIRED=5; METRIC_PODS_READY=2; METRIC_PODS_PENDING=1; render_pods_section | while IFS= read -r line; do stripped=$(echo "$line" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'); echo "len=${#stripped}: $stripped"; done
```

**Performance section:**
```bash
source scripts/dashboard/demo-dashboard.sh 2>/dev/null; METRIC_CURRENT_RPS=50; METRIC_TOKENS_PER_SEC=100; render_performance_section | while IFS= read -r line; do stripped=$(echo "$line" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'); echo "len=${#stripped}: $stripped"; done
```

**Any render function:**
```bash
source scripts/dashboard/demo-dashboard.sh 2>/dev/null; <FUNCTION_NAME> | while IFS= read -r line; do stripped=$(echo "$line" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'); echo "len=${#stripped}: $stripped"; done
```

## Before Making Changes

1. **Always run tests first**: `bats scripts/tests/demo-dashboard.bats`
2. **After changes, run tests again** to verify alignment
3. **If adding new content**, calculate the character count impact
4. **Adjust padding values** to compensate for added/removed characters
5. **Use the line length verification command** to check actual output

## Test File Location

Tests are in `scripts/tests/demo-dashboard.bats`. Key tests:
- Test 16: `render_queue_section fits in 80 columns`
- Test 17: `render_pods_section fits in 82 columns`
- Test 19: `render_performance_section fits in 80 columns`
- Test 20: `all sections combined`

## Common Pitfalls

- Adding text without reducing padding = border shifts right
- Removing text without increasing padding = border shifts left
- The stale marker `(*)` adds 2 characters when `STALE_*=true`
- ANSI color codes don't count toward visible width but affect string length in bash
