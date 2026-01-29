# Design Document: Demo Dashboard

## Overview

This design describes a terminal-based real-time dashboard for monitoring Kubernetes autoscaling demos. The dashboard is implemented as a single Bash script that collects metrics from Kubernetes and displays them in an organized, visually appealing format suitable for live conference presentations.

The dashboard uses ANSI escape codes for colors and cursor positioning to achieve flicker-free updates, and organizes information into distinct visual sections for load graphs, scaling metrics, and performance data.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Terminal Dashboard                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Data         │  │ Data         │  │ Display      │          │
│  │ Collection   │──│ Processing   │──│ Renderer     │          │
│  │ Module       │  │ Module       │  │ Module       │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│         │                                    │                  │
│         ▼                                    ▼                  │
│  ┌──────────────┐                   ┌──────────────┐           │
│  │ kubectl      │                   │ Terminal     │           │
│  │ API calls    │                   │ (stdout)     │           │
│  └──────────────┘                   └──────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

The architecture follows a simple pipeline:
1. **Data Collection**: Gathers metrics from Kubernetes via kubectl
2. **Data Processing**: Transforms raw data into displayable formats
3. **Display Renderer**: Renders the formatted data to the terminal

## Components and Interfaces

### Component 1: Data Collection Module

Responsible for gathering all metrics from the Kubernetes cluster.

```bash
# Interface functions
get_vllm_pods()        # Returns: running|desired|ready
get_vllm_queue_depth() # Returns: integer (queue depth from KEDA/HPA)
get_node_count()       # Returns: integer (GPU node count)
get_throughput()       # Returns: float (requests per second)
get_response_times()   # Returns: p50|p95|p99 or avg
get_scaling_status()   # Returns: scaling_up|scaling_down|stable
```

### Component 2: Data Processing Module

Transforms raw metrics into display-ready formats.

```bash
# Interface functions
calculate_load_history()    # Maintains rolling window of load data
format_metric_value()       # Formats numbers with units
determine_status_color()    # Returns ANSI color code based on thresholds
build_ascii_graph()         # Generates ASCII line graph from data points
calculate_percentages()     # Computes utilization percentages
```

### Component 3: Display Renderer Module

Handles all terminal output and visual formatting.

```bash
# Interface functions
render_header()             # Draws the dashboard title
render_load_graph()         # Draws the ASCII load graph
render_queue_section()      # Draws vLLM queue metrics
render_pods_section()       # Draws pod scaling status
render_nodes_section()      # Draws node scaling status
render_performance_section() # Draws throughput and response times
render_footer()             # Draws timestamp and controls
move_cursor()               # Positions cursor for updates
```

### Component 4: Graph Data Structure

Maintains historical data for the load graph.

```bash
# Data structure (implemented as arrays)
LOAD_HISTORY=()           # Array of last 60 load values
LOAD_TIMESTAMPS=()        # Array of corresponding timestamps
MAX_HISTORY_SIZE=60       # Rolling window size
GRAPH_HEIGHT=10           # Height of ASCII graph in lines
GRAPH_WIDTH=50            # Width of ASCII graph in characters
```

## Data Models

### Metric Data Model

```bash
# Current metrics snapshot
declare -A METRICS=(
    [queue_depth]=0
    [pods_running]=0
    [pods_desired]=0
    [pods_ready]=0
    [nodes_count]=0
    [throughput]=0.0
    [response_p50]=0
    [response_p95]=0
    [response_p99]=0
    [scaling_status]="stable"
    [last_update]=""
)

# Session-persistent peak metrics (only reset on dashboard restart)
SESSION_PEAK_RPS=0           # Peak requests per second observed
SESSION_PEAK_TOKENS_SEC=0    # Peak tokens per second observed

# Session-persistent performance metrics (only reset on dashboard restart)
SESSION_RPS=""               # Last good RPS value
SESSION_TOKENS_SEC=""        # Last good Tok/Sec value
SESSION_TTFT_P50=""          # Last good TTFT p50 value
SESSION_TTFT_P95=""          # Last good TTFT p95 value
SESSION_E2E_AVG=""           # Last good E2E avg value
SESSION_E2E_P50=""           # Last good E2E p50 value
SESSION_E2E_P95=""           # Last good E2E p95 value
SESSION_TOKENS_REQ=""        # Last good Tok/Req value
```

### Display Configuration

```bash
# Display settings
declare -A DISPLAY_CONFIG=(
    [refresh_interval]=2
    [graph_width]=50
    [graph_height]=10
    [terminal_width]=80
    [color_good]="\033[38;5;40m"
    [color_warning]="\033[38;5;226m"
    [color_error]="\033[38;5;196m"
    [color_info]="\033[38;5;51m"
)
```

### Threshold Configuration

```bash
# Scaling thresholds for visual indicators
declare -A THRESHOLDS=(
    [queue_target]=1          # KEDA target value
    [queue_scale_up]=5        # Queue depth triggering scale-up indication
    [response_good]=500       # Response time (ms) considered good
    [response_warning]=1000   # Response time (ms) considered degraded
    [throughput_low]=1        # Low throughput threshold
)
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Load History Bounded Size

*For any* sequence of load data additions to the history array, the array length SHALL never exceed MAX_HISTORY_SIZE (60) elements. When a new value is added and the array is at capacity, the oldest value SHALL be removed first.

**Validates: Requirements 1.2**

### Property 2: Graph Dimensions Consistency

*For any* load history data (including empty, single-element, and full arrays), the generated ASCII graph SHALL have exactly GRAPH_HEIGHT (10) lines, and each line SHALL have exactly GRAPH_WIDTH (50) printable characters (excluding ANSI escape codes).

**Validates: Requirements 1.1**

### Property 3: Load Value Presence

*For any* load value added to the history, that value SHALL appear in the history array after the addition (either as the newest element or within the rolling window if subsequent additions occurred).

**Validates: Requirements 1.3**

### Property 4: Scaling Indicator Correctness

*For any* pair of current and target/desired values (queue depth vs threshold, or running pods vs desired pods), the scaling indicator function SHALL return:
- "scale-up" indicator when current > target (for queue) or desired > running (for pods)
- "scale-down" indicator when current < target (for queue) or desired < running (for pods)  
- "stable" indicator when current equals target/desired

**Validates: Requirements 2.3, 2.4, 3.4, 3.5**

### Property 5: Graceful Degradation

*For any* metric collection function that fails (returns error or empty result), the formatted output for that metric SHALL contain "N/A" and the dashboard main loop SHALL continue executing.

**Validates: Requirements 5.4, 6.5, 8.1, 8.3**

### Property 6: Color Code Validity

*For any* call to the color determination function with any numeric input, the returned value SHALL be one of the predefined ANSI color codes (color_good, color_warning, color_error, color_info) from DISPLAY_CONFIG.

**Validates: Requirements 1.5, 5.5, 7.4**

### Property 7: Terminal Width Constraint

*For any* rendered output line from any section renderer, the printable character count (excluding ANSI escape codes) SHALL not exceed 80 characters.

**Validates: Requirements 7.3**

### Property 8: Elapsed Time Monotonicity

*For any* two consecutive calls to the elapsed time function, the second result SHALL be greater than or equal to the first result (time never goes backward).

**Validates: Requirements 6.4**

### Property 9: Performance Metrics Persistence

*For any* performance metric (RPS, Tok/Sec, TTFT, E2E latencies, Tok/Req) that has a valid non-zero value, the session-persistent variable SHALL retain that value even when subsequent metric collections return zero or N/A. The persisted value SHALL only be updated when a new valid non-zero value is collected.

**Validates: Requirements 9.1-9.8**

## Error Handling

### kubectl Command Failures

```bash
# Pattern for all kubectl calls
get_metric() {
    local result
    result=$(kubectl ... 2>/dev/null) || result="N/A"
    echo "$result"
}
```

### Cluster Connectivity

- On startup, verify cluster connectivity
- If connection fails, display error and retry every 5 seconds
- Once connected, continue with normal operation

### Invalid Data Handling

- If metric returns non-numeric data, use last known good value
- Display stale indicator (⚠) next to potentially stale values
- Log errors to `/tmp/dashboard-errors.log`

## Testing Strategy

### Unit Tests

Unit tests will verify individual functions in isolation using specific examples:

1. **Graph Generation Tests**
   - Test `build_ascii_graph` with known data points
   - Verify output dimensions match configuration
   - Test edge cases: empty data, single point, max capacity

2. **Metric Formatting Tests**
   - Test `format_metric_value` with various inputs
   - Verify correct unit suffixes (ms, RPS, etc.)
   - Test handling of N/A values

3. **Color Determination Tests**
   - Test `determine_status_color` with threshold boundaries
   - Verify correct color codes returned

4. **Display Layout Tests**
   - Verify header contains demo title
   - Verify box-drawing characters are present
   - Verify timestamp display format

### Property-Based Tests

Property-based tests will use `bats-core` with custom generators to verify universal properties:

1. **Property 1 Test: Load History Bounded Size**
   - Generate random sequences of 0-200 load additions
   - After each sequence, verify array length <= 60
   - **Feature: demo-dashboard, Property 1: Load history bounded size**

2. **Property 2 Test: Graph Dimensions Consistency**
   - Generate random load histories (0-100 elements, values 0-1000)
   - Verify output has exactly 10 lines, each with 50 printable chars
   - **Feature: demo-dashboard, Property 2: Graph dimensions consistency**

3. **Property 4 Test: Scaling Indicator Correctness**
   - Generate random pairs of (current, target) values
   - Verify correct indicator returned for each relationship
   - **Feature: demo-dashboard, Property 4: Scaling indicator correctness**

4. **Property 5 Test: Graceful Degradation**
   - Generate random kubectl failure scenarios
   - Verify "N/A" appears in output and loop continues
   - **Feature: demo-dashboard, Property 5: Graceful degradation**

5. **Property 6 Test: Color Code Validity**
   - Generate random numeric inputs across full range
   - Verify returned color is in predefined set
   - **Feature: demo-dashboard, Property 6: Color code validity**

6. **Property 7 Test: Terminal Width Constraint**
   - Generate random metric values (including edge cases)
   - Render each section and verify no line exceeds 80 chars
   - **Feature: demo-dashboard, Property 7: Terminal width constraint**

7. **Property 9 Test: Performance Metrics Persistence**
   - Generate sequences with valid values followed by zeros/N/A
   - Verify session variables retain last good values
   - Verify display shows persisted values when current is zero/N/A
   - **Feature: demo-dashboard, Property 9: Performance metrics persistence**

### Integration Tests

1. **End-to-End Display Test**: Run dashboard with mock kubectl responses
2. **Refresh Cycle Test**: Verify 2-second update interval
3. **Terminal Compatibility Test**: Verify display on different terminal sizes

### Test Configuration

- Use `bats-core` for Bash unit testing
- Minimum 100 iterations for property-based tests
- Mock kubectl responses using function overrides
- Tag format: **Feature: demo-dashboard, Property N: property_description**
