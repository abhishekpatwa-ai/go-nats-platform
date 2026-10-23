# ---------- 2. EKS cluster, nodes, add-ons ----------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.name
  cluster_version = "1.34"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access           = true # lab: kubectl from the laptop
  enable_cluster_creator_admin_permissions = true # your SSO role = cluster admin (access entry)

  cluster_addons = {
    vpc-cni                = {} # pod IPs from the VPC
    coredns                = {} # service DNS
    kube-proxy             = {} # Service -> pod rules
    eks-pod-identity-agent = {} # IAM roles for pods
    aws-ebs-csi-driver     = {} # EBS disks for PostgreSQL and NATS (PVCs)
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 3 # Prometheus + NATS + Postgres + app need a bit of room
    }
  }

  # GitHub Actions role -> Kubernetes group "github-deployers".
  # What that group may do is a Role in the app namespace only (app-access.tf): least privilege.
  access_entries = {
    github = {
      principal_arn     = aws_iam_role.github_deploy.arn
      kubernetes_groups = ["github-deployers"]
    }
  }
}

# EBS CSI driver gets its IAM role through Pod Identity
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.12"

  name                      = "${var.name}-ebs-csi"
  attach_aws_ebs_csi_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
}

# Default StorageClass (newer EKS versions don't ship a default one)
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name        = "gp3"
    annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"               # disk is deleted with the PVC
  volume_binding_mode    = "WaitForFirstConsumer" # create the disk in the pod's AZ
  allow_volume_expansion = true
  parameters             = { type = "gp3", encrypted = "true" }

  depends_on = [module.eks]
}
