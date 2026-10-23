# ---------- 1. Network: VPC across 2 AZs ----------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

  name = var.name
  cidr = "10.60.0.0/16"

  azs             = ["${var.region}a", "${var.region}b"]
  public_subnets  = ["10.60.101.0/24", "10.60.102.0/24"] # ALB + NAT
  private_subnets = ["10.60.1.0/24", "10.60.2.0/24"]     # nodes + pods

  enable_nat_gateway = true
  single_nat_gateway = true # lab: one NAT (prod: one per AZ)

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }          # where internet-facing ALBs go
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 } # where internal ALBs go
}
