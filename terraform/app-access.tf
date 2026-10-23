# ---------- 6. Namespace + RBAC for the pipeline ----------
# EKS access entry (eks.tf) maps the GitHub role to the Kubernetes group "github-deployers".
# This Role says what that group may do — only inside the app namespace.

resource "kubernetes_namespace_v1" "app" {
  metadata { name = var.app_namespace }
  depends_on = [module.eks]
}

resource "kubernetes_role_v1" "deployer" {
  metadata {
    name      = "github-deployer"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["secrets", "services", "configmaps", "serviceaccounts", "persistentvolumeclaims", "pods", "pods/log", "events"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["monitoring.coreos.com"]
    resources  = ["servicemonitors"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "deployer" {
  metadata {
    name      = "github-deployer"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.deployer.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "github-deployers"
    api_group = "rbac.authorization.k8s.io"
  }
}
