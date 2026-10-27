# ---------- 4. Shared platform services: NATS + monitoring ----------
# Installed once by Terraform. The app itself is deployed by the pipeline with its own Helm chart.

# NATS with JetStream (messages are stored on disk, so a stopped worker loses nothing)
resource "helm_release" "nats" {
  name             = "nats"
  repository       = "https://nats-io.github.io/k8s/helm/charts/"
  chart            = "nats"
  namespace        = "nats"
  create_namespace = true

  values = [yamlencode({
    config = {
      jetstream = {
        enabled   = true
        fileStore = { pvc = { size = "2Gi" } } # EBS disk via the gp3 StorageClass
      }
    }
    # Prometheus exporter sidecar + PodMonitor so Grafana can show NATS metrics
    promExporter = {
      enabled    = true
      podMonitor = { enabled = true }
    }
  })]

  depends_on = [kubernetes_storage_class_v1.gp3, helm_release.monitoring]
}

# Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics
resource "helm_release" "monitoring" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 900

  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        # pick up ServiceMonitors/PodMonitors from every namespace, not only this release's
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        retention                               = "1d"
      }
    }
    grafana = { service = { type = "ClusterIP" } } # open with kubectl port-forward
  })]

  # The LB Controller registers a webhook that checks every new Service. If this chart
  # creates Services before the controller's pods are ready, the webhook has no endpoints
  # and the install fails — so wait for the controller first.
  depends_on = [module.eks, helm_release.aws_lbc]
}
