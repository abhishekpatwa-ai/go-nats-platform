variable "name" {
  description = "Prefix for every resource"
  type        = string
  default     = "go-nats"
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "github_repo" {
  description = "Repo allowed to deploy through GitHub OIDC"
  type        = string
  default     = "abhishekpatwa-ai/go-nats-platform"
}

variable "github_owner_id" {
  description = "GitHub numeric owner ID (GitHub now puts IDs in the OIDC subject)"
  type        = string
  default     = "336658880"
}

variable "app_namespace" {
  description = "Namespace the pipeline deploys the app into"
  type        = string
  default     = "app"
}
