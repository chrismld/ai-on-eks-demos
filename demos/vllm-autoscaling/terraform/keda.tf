# Kedify Agent with KEDA and add-ons (unified installation)
resource "helm_release" "kedify_agent" {
  name             = "kedify-agent"
  namespace        = "keda"
  create_namespace = true

  repository = "https://kedify.github.io/charts"
  chart      = "kedify-agent"
  version    = "v0.4.9"

  values = [<<-EOT
    clusterName: ai-workloads-tube-demo
    agent:
      orgId: "00000000-0000-0000-0000-000000000000"
      agentId: "00000000-0000-0000-0000-000000000000"
      apiKey: "kfy_0000000000000000000000000000000000000000000000000000000000000000"
      extraArgs:
        offline: true
    
    # Enable KEDA core
    keda:
      enabled: true
      image:
        pullPolicy: IfNotPresent
      env:
        - name: RAW_METRICS_GRPC_PROTOCOL
          value: enabled
    
    # Enable KEDA HTTP add-on
    keda-add-ons-http:
      enabled: true
    
    # Enable OTEL add-on for metric-based scaling
    otel-add-on:
      enabled: true
      otelOperator:
        enabled: true
      otelOperatorCrs:
      - name: scrape-vllm
        enabled: true
        prometheusScrapeConfigs:
        - job_name: 'vllm-metrics'
          scrape_interval: 5s
          kubernetes_sd_configs:
          - role: pod
            namespaces:
              names:
              - default
          relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app]
            regex: "vllm"
            action: keep
          - source_labels: [__meta_kubernetes_pod_name]
            action: replace
            target_label: pod_name
          - source_labels: [__address__]
            action: replace
            target_label: __address__
            regex: (.+):.*
            replacement: $1:8080
        includeMetrics:
        - vllm_num_requests_waiting
    
    # Enable Kedify predictor
    kedify-predictor:
      enabled: true
  EOT
  ]

  depends_on = [helm_release.aws_load_balancer_controller, helm_release.metrics_server]
}
