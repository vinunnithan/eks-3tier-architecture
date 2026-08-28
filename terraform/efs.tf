# ============================================================
# EFS FILESYSTEM FOR MYSQL — SHARED STORAGE
# ============================================================

module "efs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-efs-csi-role"

  attach_efs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }
}

resource "aws_security_group" "efs" {
  name   = "${var.project_name}-efs-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "mysql_data" {
  creation_token = "${var.project_name}-mysql-efs"

  tags = {
    Project = var.project_name
    Name    = "${var.project_name}-mysql-efs"
  }
}

resource "aws_efs_mount_target" "mysql_data" {
  for_each = toset(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.mysql_data.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "kubernetes_storage_class" "efs" {
  metadata {
    name = "efs-sc"
  }

  storage_provisioner = "efs.csi.aws.com"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.mysql_data.id
    directoryPerms   = "755"
    gid              = "999"
    uid              = "999"
    basePath         = "/dynamic_provisioning"
  }

  depends_on = [module.eks]
}

output "efs_file_system_id" {
  value = aws_efs_file_system.mysql_data.id
}