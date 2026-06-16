resource "kubernetes_namespace" "apps" {
  metadata { name = "apps" }
  depends_on = [aws_eks_fargate_profile.fp_datadog_lab]
}

resource "kubernetes_service_account" "datadog_agent" {
  metadata {
    name      = "datadog-agent"
    namespace = kubernetes_namespace.apps.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "datadog_agent" {
  metadata { name = "datadog-agent" }

  rule {
    api_groups = [""]
    resources  = ["nodes", "pods", "services", "endpoints", "events", "namespaces", "componentstatuses"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["nodes/proxy", "nodes/stats", "nodes/metrics"]
    verbs      = ["get"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "datadog_agent" {
  metadata { name = "datadog-agent" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.datadog_agent.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.datadog_agent.metadata[0].name
    namespace = kubernetes_namespace.apps.metadata[0].name
  }
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "python-app"
    namespace = kubernetes_namespace.apps.metadata[0].name
  }

  spec {
    replicas = 1

    selector { match_labels = { app = "python-app" } }

    template {
      metadata {
        labels = {
          app     = "python-app"
          version = "1.0.0"
          env     = "production"
        }
        annotations = {
          "ad.datadoghq.com/datadog-agent.checks" = jsonencode({
            kubernetes_state = {
              init_config = {}
              instances = [{
                kube_state_url = "http://kube-state-metrics.kube-system.svc.cluster.local:8080/metrics"
                telemetry      = true
              }]
            }
          })
          "ad.datadoghq.com/python-app.logs" = jsonencode([{
            source  = "python"
            service = "python-app"
          }])
        }
      }

      spec {
        service_account_name = kubernetes_service_account.datadog_agent.metadata[0].name

        volume {
          name = "agent-run"
          empty_dir {}
        }

        # ── App container ──────────────────────────────────────────────────────
        container {
          name  = "python-app"
          image = "987615086900.dkr.ecr.us-east-1.amazonaws.com/python-tracing-app:latest"

          env {
            name  = "DD_AGENT_HOST"
            value = "localhost"
          }
          env {
            name  = "DD_TRACE_AGENT_PORT"
            value = "8126"
          }
          env {
            name  = "DD_ENV"
            value = "production"
          }
          env {
            name  = "DD_SERVICE"
            value = "python-app"
          }
          env {
            name  = "DD_VERSION"
            value = "1.0.0"
          }
          env {
            name  = "DD_TRACE_SAMPLE_RATE"
            value = "1.0"
          }
          env {
            name  = "DD_LOGS_INJECTION"
            value = "true"
          }
        }

        # ── Datadog Agent sidecar ──────────────────────────────────────────────
        container {
          name  = "datadog-agent"
          image = "public.ecr.aws/datadog/agent:latest"

          env {
            name  = "DD_API_KEY"
            value = var.dd_api_key
          }
          env {
            name  = "DD_SITE"
            value = "datadoghq.com"
          }
          env {
            name  = "DD_EKS_FARGATE"
            value = "true"
          }
          env {
            name  = "DD_APM_ENABLED"
            value = "true"
          }
          env {
            name  = "DD_APM_NON_LOCAL_TRAFFIC"
            value = "true"
          }
          env {
            name  = "DD_ENV"
            value = "production"
          }
          env {
            name  = "DD_SERVICE"
            value = "python-app"
          }
          env {
            name  = "DD_VERSION"
            value = "1.0.0"
          }
          env {
            name  = "DD_CLUSTER_NAME"
            value = var.cluster_name
          }
          env {
            name  = "DD_CLUSTER_AGENT_ENABLED"
            value = "true"
          }
          env {
            name  = "DD_CLUSTER_AGENT_AUTH_TOKEN"
            value = "wIQOziFv7lNG3WhaUpikhotEH4x4uWwX"
          }
          env {
            name  = "DD_CLUSTER_AGENT_URL"
            value = "https://datadog-agent-cluster-agent.datadog.svc.cluster.local:5005"
          }
          env {
            name = "DD_KUBERNETES_KUBELET_NODENAME"
            value_from {
              field_ref { field_path = "spec.nodeName" }
            }
          }
          env {
            name  = "DD_ORCHESTRATOR_EXPLORER_ENABLED"
            value = "true"
          }
          env {
            name  = "DD_ORCHESTRATOR_EXPLORER_CONTAINER_SCRUBBING_ENABLED"
            value = "true"
          }
          env {
            name  = "DD_KUBERNETES_COLLECT_METADATA_TAGS"
            value = "true"
          }
          env {
            name  = "DD_COLLECT_KUBERNETES_EVENTS"
            value = "true"
          }
          env {
            name  = "DD_LEADER_ELECTION"
            value = "true"
          }
          env {
            name  = "DD_KUBERNETES_POD_LABELS_AS_TAGS"
            value = jsonencode({ app = "app", version = "version", env = "env" })
          }
          env {
            name  = "DD_LOGS_ENABLED"
            value = "true"
          }
          env {
            name  = "DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL"
            value = "true"
          }
          env {
            name  = "DD_LOGS_CONFIG_K8S_CONTAINER_USE_KUBELET_API"
            value = "true"
          }
          env {
            name  = "DD_LOGS_CONFIG_RUN_PATH"
            value = "/opt/datadog-agent/run"
          }
          env {
            name  = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC"
            value = "true"
          }
          env {
            name  = "DD_PROCESS_AGENT_ENABLED"
            value = "true"
          }

          port {
            container_port = 8126
            protocol       = "TCP"
          }
          port {
            container_port = 8125
            protocol       = "UDP"
          }

          volume_mount {
            name       = "agent-run"
            mount_path = "/opt/datadog-agent/run"
          }
        }
      }
    }
  }
}
