# Implementation Plan: Demo Dashboard

## Overview

This plan implements a terminal-based real-time dashboard for monitoring Kubernetes autoscaling demos. The implementation is a single Bash script with modular functions for data collection, processing, and display rendering.

## Tasks

- [x] 1. Set up project structure and configuration
  - Create the main dashboard script file `scripts/demo-dashboard.sh`
  - Define color constants and ANSI escape codes
  - Define configuration variables (refresh interval, graph dimensions, thresholds)
  - Define data structure arrays for metrics and history
  - _Requirements: 7.4, 6.1_

- [x] 2. Implement data collection functions
  - [x] 2.1 Implement `get_vllm_pods` function
    - Query kubectl for vLLM deployment status
    - Return running|desired|ready pipe-separated values
    - Handle kubectl failures gracefully with "N/A"
    - _Requirements: 3.1, 3.2, 3.3, 8.1_

  - [x] 2.2 Implement `get_queue_depth` function
    - Query KEDA/HPA for current metric value
    - Parse vllm_num_requests_waiting metric
    - Return integer value or "N/A" on failure
    - _Requirements: 2.1, 8.1_

  - [x] 2.3 Implement `get_node_info` function
    - Query kubectl for GPU nodes (label: karpenter.sh/nodepool)
    - Return node count and instance type
    - Handle missing nodes gracefully
    - _Requirements: 4.1, 4.2, 8.1_

  - [x] 2.4 Implement `get_performance_metrics` function
    - Attempt to get throughput from API metrics endpoint
    - Attempt to get response time percentiles
    - Fall back to "N/A" when unavailable
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [x] 3. Implement data processing functions
  - [x] 3.1 Implement `add_to_load_history` function
    - Add new value to LOAD_HISTORY array
    - Remove oldest value if array exceeds MAX_HISTORY_SIZE
    - Maintain corresponding timestamps
    - _Requirements: 1.2, 1.3_

  - [x] 3.2 Write property test for load history bounded size
    - **Property 1: Load history bounded size**
    - Generate random sequences of additions
    - Verify array never exceeds 60 elements
    - **Validates: Requirements 1.2**

  - [x] 3.3 Implement `determine_scaling_status` function
    - Compare current vs desired/target values
    - Return "scaling_up", "scaling_down", or "stable"
    - Handle both pod and queue depth comparisons
    - _Requirements: 2.3, 2.4, 3.4, 3.5_

  - [x] 3.4 Write property test for scaling indicator correctness
    - **Property 4: Scaling indicator correctness**
    - Generate random (current, target) pairs
    - Verify correct indicator for each relationship
    - **Validates: Requirements 2.3, 2.4, 3.4, 3.5**

  - [x] 3.5 Implement `determine_status_color` function
    - Accept metric type and value
    - Return appropriate ANSI color code based on thresholds
    - Always return a valid color from predefined set
    - _Requirements: 1.5, 5.5, 7.4_

  - [x] 3.6 Write property test for color code validity
    - **Property 6: Color code validity**
    - Generate random numeric inputs
    - Verify returned color is in predefined set
    - **Validates: Requirements 1.5, 5.5, 7.4**

- [x] 4. Implement ASCII graph rendering
  - [x] 4.1 Implement `build_ascii_graph` function
    - Accept load history array as input
    - Generate GRAPH_HEIGHT lines of GRAPH_WIDTH characters
    - Scale values to fit graph height
    - Use block characters for visualization
    - _Requirements: 1.1_

  - [x] 4.2 Write property test for graph dimensions
    - **Property 2: Graph dimensions consistency**
    - Generate random load histories
    - Verify output is exactly 10 lines x 50 chars
    - **Validates: Requirements 1.1**

  - [x] 4.3 Implement `strip_ansi` helper function
    - Remove ANSI escape codes from string
    - Used for measuring printable character count
    - _Requirements: 7.3_

- [x] 5. Implement display renderer functions
  - [x] 5.1 Implement `render_header` function
    - Display dashboard title with box-drawing characters
    - Include timestamp and elapsed time
    - Fit within 80 columns
    - _Requirements: 7.2, 7.5, 6.3, 6.4_

  - [x] 5.2 Implement `render_load_section` function
    - Display ASCII load graph
    - Show current RPS value
    - Show load intensity indicator with color
    - _Requirements: 1.1, 1.4, 1.5_

  - [x] 5.3 Implement `render_queue_section` function
    - Display queue depth prominently
    - Show KEDA target threshold
    - Show scaling zone indicator (scale-up/stable/scale-down)
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x] 5.4 Implement `render_pods_section` function
    - Display running/desired/ready pod counts
    - Show visual pod representation (icons)
    - Show scaling direction indicator
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

  - [x] 5.5 Implement `render_nodes_section` function
    - Display GPU node count
    - Show visual node representation
    - _Requirements: 4.1, 4.2, 4.3_

  - [x] 5.6 Implement `render_performance_section` function
    - Display throughput (RPS)
    - Display response times (p50, p95, p99 or avg)
    - Use color coding for performance status
    - Handle N/A gracefully
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [x] 5.7 Write property test for terminal width constraint
    - **Property 7: Terminal width constraint**
    - Render each section with random metric values
    - Verify no line exceeds 80 printable characters
    - **Validates: Requirements 7.3**

- [x] 6. Implement main dashboard loop
  - [x] 6.1 Implement `collect_all_metrics` function
    - Call all data collection functions
    - Store results in METRICS associative array
    - Track last successful values for stale handling
    - _Requirements: 6.5, 8.3_

  - [x] 6.2 Write property test for graceful degradation
    - **Property 5: Graceful degradation**
    - Mock kubectl failures
    - Verify "N/A" appears and loop continues
    - **Validates: Requirements 5.4, 6.5, 8.1, 8.3**

  - [x] 6.3 Implement `render_dashboard` function
    - Clear screen using cursor positioning (not full clear)
    - Call all render functions in order
    - Display footer with controls
    - _Requirements: 6.2, 7.1_

  - [x] 6.4 Implement main loop with 2-second refresh
    - Initialize start time for elapsed calculation
    - Loop: collect metrics → update history → render
    - Sleep for refresh interval
    - Handle Ctrl+C gracefully
    - _Requirements: 6.1, 6.4_

- [x] 7. Implement startup checks and error handling
  - [x] 7.1 Implement prerequisite checks
    - Verify kubectl is installed
    - Verify cluster connectivity
    - Verify vllm namespace exists
    - Display helpful error messages on failure
    - _Requirements: 8.2_

  - [x] 7.2 Implement error logging
    - Create log file at /tmp/demo-dashboard.log
    - Log errors without disrupting display
    - Include timestamps in log entries
    - _Requirements: 8.4_

  - [x] 7.3 Implement signal handlers
    - Trap SIGINT and SIGTERM
    - Restore cursor visibility on exit
    - Display goodbye message
    - _Requirements: 8.3_

- [x] 8. Checkpoint - Verify core functionality
  - Ensure all data collection functions work with live cluster
  - Ensure display renders correctly in terminal
  - Ensure 2-second refresh works without flicker
  - Ask the user if questions arise.

- [x] 9. Integration and polish
  - [x] 9.1 Wire all components together
    - Ensure main script is executable
    - Add shebang and script header comments
    - Test full dashboard flow
    - _Requirements: All_

  - [x] 9.2 Add visual polish
    - Fine-tune colors and spacing
    - Ensure consistent alignment
    - Add key insights footer section
    - _Requirements: 7.1, 7.4_

- [x] 10. Final checkpoint
  - Run dashboard against live cluster
  - Verify all metrics display correctly
  - Verify scaling indicators work during load test
  - Ensure all tests pass, ask the user if questions arise.

- [x] 11. Implement performance metrics persistence
  - [x] 11.1 Add session-persistent performance metric variables
    - Add `SESSION_RPS`, `SESSION_TOKENS_SEC` variables initialized to empty
    - Add `SESSION_TTFT_P50`, `SESSION_TTFT_P95` variables initialized to empty
    - Add `SESSION_E2E_AVG`, `SESSION_E2E_P50`, `SESSION_E2E_P95` variables initialized to empty
    - Add `SESSION_TOKENS_REQ` variable initialized to empty
    - Variables should only reset when dashboard restarts
    - _Requirements: 9.1-9.5, 9.7, 9.8_

  - [x] 11.2 Update `get_performance_metrics` to persist last good values
    - When RPS is valid (non-zero, non-N/A), update `SESSION_RPS`
    - When Tok/Sec is valid, update `SESSION_TOKENS_SEC`
    - When TTFT values are valid, update `SESSION_TTFT_P50`, `SESSION_TTFT_P95`
    - When E2E values are valid, update `SESSION_E2E_AVG`, `SESSION_E2E_P50`, `SESSION_E2E_P95`
    - When Tok/Req is valid, update `SESSION_TOKENS_REQ`
    - _Requirements: 9.1-9.5_

  - [x] 11.3 Update `render_performance_section` to use persisted values
    - Display `SESSION_*` values when current values are zero or N/A
    - Ensure display fits within 80-column constraint per steering rules
    - Run `bats scripts/tests/demo-dashboard.bats` to verify alignment
    - _Requirements: 9.6, 9.7_

  - [ ]* 11.4 Write property test for performance metrics persistence
    - **Property 9: Performance metrics persistence**
    - Generate sequences with valid values followed by zeros/N/A
    - Verify session variables retain last good values
    - **Validates: Requirements 9.1-9.8**

## Notes

- All property-based tests are required for comprehensive coverage
- The implementation is a single Bash script for simplicity
- Uses bats-core for testing (install with: `brew install bats-core`)
- Property tests require custom generators implemented in Bash
- Each task references specific requirements for traceability
