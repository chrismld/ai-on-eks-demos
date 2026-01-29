# Requirements Document

## Introduction

A terminal-based real-time dashboard for monitoring Kubernetes autoscaling demos. The dashboard displays load test metrics, vLLM queue depth, pod/node scaling status, and performance metrics (throughput and response times) in a visually appealing format suitable for live conference demonstrations.

## Glossary

- **Dashboard**: The terminal-based monitoring interface that displays real-time metrics
- **vLLM**: The LLM inference server being scaled
- **KEDA**: Kubernetes Event-Driven Autoscaler that scales vLLM based on queue depth
- **Karpenter**: Kubernetes node autoscaler that provisions GPU nodes on demand
- **Queue_Depth**: The number of requests waiting to be processed by vLLM (vllm_num_requests_waiting metric)
- **Load_Graph**: ASCII-based visual representation of load over time
- **Throughput**: Number of requests processed per second
- **Response_Time**: Time taken to process a request (p50, p95, p99 percentiles)

## Requirements

### Requirement 1: Load Visualization

**User Story:** As a demo presenter, I want to see a visual graph of the load increasing over time, so that the audience can understand the traffic pattern.

#### Acceptance Criteria

1. THE Dashboard SHALL display an ASCII-based line graph showing request load over time
2. THE Dashboard SHALL maintain a rolling window of the last 60 data points for the load graph
3. WHEN new load data is collected, THE Dashboard SHALL update the graph with the latest value
4. THE Dashboard SHALL display the current requests per second (RPS) as a numeric value alongside the graph
5. THE Dashboard SHALL use visual indicators (colors or symbols) to show load intensity levels

### Requirement 2: vLLM Queue Metric Display

**User Story:** As a demo presenter, I want to see the vLLM queue depth metric prominently displayed, so that I can explain the scaling trigger to the audience.

#### Acceptance Criteria

1. THE Dashboard SHALL display the current vLLM queue depth (vllm_num_requests_waiting) as a prominent numeric value
2. THE Dashboard SHALL display the KEDA target threshold value for comparison
3. WHEN the queue depth exceeds the target threshold, THE Dashboard SHALL visually indicate a scale-up condition
4. WHEN the queue depth is below the target threshold, THE Dashboard SHALL visually indicate a stable or scale-down condition
5. THE Dashboard SHALL update the queue depth value every 2 seconds

### Requirement 3: Pod Scaling Status

**User Story:** As a demo presenter, I want to see the number of vLLM pods and their scaling status, so that I can demonstrate Kubernetes horizontal scaling.

#### Acceptance Criteria

1. THE Dashboard SHALL display the current number of running vLLM pods
2. THE Dashboard SHALL display the desired number of vLLM pods
3. THE Dashboard SHALL display the number of ready pods
4. WHEN pods are scaling up, THE Dashboard SHALL display a visual indicator showing the scaling direction
5. WHEN pods are scaling down, THE Dashboard SHALL display a visual indicator showing the scaling direction
6. THE Dashboard SHALL display a visual representation of pods (e.g., icons or progress bar) showing current vs maximum capacity

### Requirement 4: Node Scaling Status

**User Story:** As a demo presenter, I want to see the number of GPU nodes provisioned by Karpenter, so that I can demonstrate infrastructure scaling.

#### Acceptance Criteria

1. THE Dashboard SHALL display the current number of active GPU nodes
2. WHEN new nodes are being provisioned, THE Dashboard SHALL indicate node scaling activity
3. THE Dashboard SHALL display a visual representation of nodes showing current count

### Requirement 5: Performance Metrics Display

**User Story:** As a demo presenter, I want to see throughput and response time metrics, so that I can demonstrate the system's performance characteristics.

#### Acceptance Criteria

1. THE Dashboard SHALL display current throughput in requests per second
2. THE Dashboard SHALL display response time percentiles (p50, p95, p99) when available
3. THE Dashboard SHALL display average response time when percentiles are not available
4. IF response time data is unavailable, THEN THE Dashboard SHALL display "N/A" gracefully
5. THE Dashboard SHALL use color coding to indicate performance status (green for good, yellow for degraded, red for poor)

### Requirement 6: Real-Time Updates

**User Story:** As a demo presenter, I want the dashboard to update in real-time without flickering, so that the display looks professional during the demo.

#### Acceptance Criteria

1. THE Dashboard SHALL refresh all metrics every 2 seconds
2. THE Dashboard SHALL use terminal cursor positioning to update values without full screen redraws
3. THE Dashboard SHALL display a timestamp showing the last update time
4. THE Dashboard SHALL display the elapsed time since the dashboard started
5. IF a metric collection fails, THEN THE Dashboard SHALL display the last known value with a stale indicator

### Requirement 7: Visual Layout

**User Story:** As a demo presenter, I want a clean, organized layout that fits on a standard terminal, so that all metrics are visible at once.

#### Acceptance Criteria

1. THE Dashboard SHALL organize metrics into clearly labeled sections
2. THE Dashboard SHALL use box-drawing characters for visual separation
3. THE Dashboard SHALL fit within an 80-column terminal width
4. THE Dashboard SHALL use consistent color coding throughout
5. THE Dashboard SHALL display a header with the demo title

### Requirement 8: Error Handling

**User Story:** As a demo presenter, I want the dashboard to handle errors gracefully, so that the demo continues even if some metrics are temporarily unavailable.

#### Acceptance Criteria

1. IF kubectl commands fail, THEN THE Dashboard SHALL display "N/A" for affected metrics
2. IF the Kubernetes cluster is unreachable, THEN THE Dashboard SHALL display an error message and retry
3. THE Dashboard SHALL continue running even if individual metric collections fail
4. THE Dashboard SHALL log errors to a file without disrupting the display

### Requirement 9: Performance Metrics Persistence

**User Story:** As a demo presenter, I want all performance metrics to persist their values after the load test completes, so that I can show the final results screen with meaningful data instead of N/A values.

#### Acceptance Criteria

1. THE Dashboard SHALL persist the last non-zero/non-N/A value for RPS during the session
2. THE Dashboard SHALL persist the last non-zero/non-N/A value for Tok/Sec during the session
3. THE Dashboard SHALL persist the last non-zero/non-N/A value for TTFT p50 and p95 during the session
4. THE Dashboard SHALL persist the last non-zero/non-N/A value for E2E Avg, p50, and p95 during the session
5. THE Dashboard SHALL persist the last non-zero/non-N/A value for Tok/Req during the session
6. WHEN the load test completes and traffic drops to zero, THE Dashboard SHALL continue displaying the persisted performance values
7. THE persisted values SHALL only reset when the dashboard is restarted, not when metrics temporarily become unavailable or zero
8. THE Dashboard SHALL use session-persistent variables (similar to pod startup times) for all performance metrics
