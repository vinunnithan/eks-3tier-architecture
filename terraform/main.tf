terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}

provider "aws" {
  region = var.aws_region
}


# ============================================================
# VARIABLES
# ============================================================

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "poc2-three-tier"
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability Zones"
  type        = list(string)

  default = [
    "eu-west-1a",
    "eu-west-1b"
  ]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)

  default = [
    "10.0.0.0/24",
    "10.0.1.0/24"
  ]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  type        = list(string)

  default = [
    "10.0.2.0/24",
    "10.0.3.0/24"
  ]
}

variable "cluster_version" {
  description = "EKS Kubernetes Version"
  type        = string
  default     = "1.36"
}


# ============================================================
# JENKINS EC2 IAM ROLE
# ============================================================

variable "jenkins_ec2_role_arn" {
  description = "IAM Role ARN attached to Jenkins EC2"
  type        = string
  default     = "arn:aws:iam::231733667519:role/ssm-role"
}


# ============================================================
# KUBERNETES PROVIDER
# ============================================================

provider "kubernetes" {
  host = module.eks.cluster_endpoint

  cluster_ca_certificate = base64decode(
    module.eks.cluster_certificate_authority_data
  )

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"

    args = [
      "eks",
      "get-token",
      "--region",
      var.aws_region,
      "--cluster-name",
      module.eks.cluster_name
    ]
  }
}

provider "helm" {
  kubernetes {
    host = module.eks.cluster_endpoint

    cluster_ca_certificate = base64decode(
      module.eks.cluster_certificate_authority_data
    )

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"

      args = [
        "eks",
        "get-token",
        "--region",
        var.aws_region,
        "--cluster-name",
        module.eks.cluster_name
      ]
    }
  }
}

# ============================================================
# VPC
# ============================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }

  tags = {
    Project = var.project_name
  }
}


# ============================================================
# EKS CLUSTER
# ============================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-cluster"
  cluster_version = var.cluster_version

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      name = "${var.project_name}-ng"

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      min_size     = 2
      max_size     = 4
      desired_size = 3

      subnet_ids = module.vpc.private_subnets
    }
  }

  cluster_addons = {

    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
    aws-efs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.efs_csi_irsa_role.iam_role_arn
    }

    coredns = {
      most_recent = true
    }

    kube-proxy = {
      most_recent = true
    }

    vpc-cni = {
      most_recent = true

      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }

    amazon-cloudwatch-observability = {
      most_recent              = true
      service_account_role_arn = module.cloudwatch_observability_irsa_role.iam_role_arn
    }
  }

  tags = {
    Project = var.project_name
  }
}

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-ebs-csi-role"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn

      namespace_service_accounts = [
        "kube-system:ebs-csi-controller-sa"
      ]
    }
  }
}

# ============================================================
# CLOUDWATCH IRSA ROLE
# ============================================================

module "cloudwatch_observability_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-cloudwatch-observability-role"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["amazon-cloudwatch:cloudwatch-agent"]
    }
  }
}

# ============================================================
# ECR REPOSITORIES
# ============================================================

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project_name}-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# JENKINS EC2 — EKS ACCESS
# ============================================================

resource "aws_eks_access_entry" "jenkins" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.jenkins_ec2_role_arn
  type          = "STANDARD"

  depends_on = [
    module.eks
  ]
}

resource "aws_eks_access_policy_association" "jenkins_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.jenkins_ec2_role_arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.jenkins
  ]
}

# ============================================================
# NAMESPACES — dev / qa / prod
# ============================================================

resource "kubernetes_namespace" "environments" {
  for_each = toset(["dev", "qa", "prod"])

  metadata {
    name = each.key
  }

  depends_on = [
    module.eks,
    aws_eks_access_entry.jenkins
  ]
}

# ============================================================
# EXTERNAL SECRETS — IRSA
# ============================================================

resource "aws_iam_policy" "external_secrets_read" {
  name = "${var.project_name}-external-secrets-read-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = "arn:aws:secretsmanager:*:*:secret:poc2/*"
      }
    ]
  })
}

module "external_secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-external-secrets-role"

  role_policy_arns = {
    policy = aws_iam_policy.external_secrets_read.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }
}

# ============================================================
# STORAGE CLASS
# ============================================================

resource "kubernetes_storage_class" "ebs_gp3" {
  metadata {
    name = "ebs-gp3"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }

  depends_on = [
    module.eks
  ]
}

# ============================================================
# NGINX INGRESS CONTROLLER — HELM
# ============================================================

resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  chart            = "${path.module}/charts-cache/ingress-nginx-4.11.3.tgz"
  namespace        = "ingress-nginx"
  create_namespace = true

  depends_on = [module.eks]
}

# ============================================================
# METRICS SERVER — HELM
# ============================================================

resource "helm_release" "metrics_server" {
  name      = "metrics-server"
  chart     = "${path.module}/charts-cache/metrics-server-3.12.1.tgz"
  namespace = "kube-system"

  depends_on = [
    module.eks
  ]
}

# ============================================================
# EXTERNAL SECRETS OPERATOR — HELM
# ============================================================

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  chart            = "${path.module}/charts-cache/external-secrets-0.10.7.tgz"
  namespace        = "external-secrets"
  create_namespace = true

  depends_on = [module.eks]
}

resource "kubernetes_annotations" "external_secrets_sa" {
  api_version = "v1"
  kind        = "ServiceAccount"

  metadata {
    name      = "external-secrets"
    namespace = "external-secrets"
  }

  annotations = {
    "eks.amazonaws.com/role-arn" = module.external_secrets_irsa_role.iam_role_arn
  }

  depends_on = [helm_release.external_secrets]
}

# ============================================================
# CLUSTER SECRET STORE — shared across dev/qa/prod
# ============================================================
resource "null_resource" "cluster_secret_store" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}
      kubectl apply -f - <<EOF
      apiVersion: external-secrets.io/v1beta1
      kind: ClusterSecretStore
      metadata:
        name: aws-secrets-store
      spec:
        provider:
          aws:
            service: SecretsManager
            region: ${var.aws_region}
            auth:
              jwt:
                serviceAccountRef:
                  name: external-secrets
                  namespace: external-secrets
      EOF
    EOT
  }

  depends_on = [helm_release.external_secrets]
}

# ============================================================
# OUTPUTS
# ============================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  description = "EKS node security group ID"
  value       = module.eks.node_security_group_id
}

output "ecr_backend_repo_url" {
  description = "Backend ECR repository"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repo_url" {
  description = "Frontend ECR repository"
  value       = aws_ecr_repository.frontend.repository_url
}

output "external_secrets_role_arn" {
  description = "IAM role ARN for External Secrets Operator"
  value       = module.external_secrets_irsa_role.iam_role_arn
}