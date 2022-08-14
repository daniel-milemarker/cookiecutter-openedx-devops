#------------------------------------------------------------------------------
#
# see: https://karpenter.sh/v0.13.2/getting-started/getting-started-with-terraform/
#
# requirements: you must initialize a local helm repo in order to run
# this mdoule.
#
#   brew install helm
#   helm repo add karpenter https://charts.karpenter.sh/
#   helm repo update
#
# NOTE: run `helm repo update` prior to running this
#       Terraform module.
#-----------------------------------------------------------
resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = "{{ cookiecutter.terraform_helm_karpenter }}"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter_irsa.iam_role_arn
  }

  set {
    name  = "clusterName"
    value = module.eks.cluster_id
  }

  set {
    name  = "clusterEndpoint"
    value = module.eks.cluster_endpoint
  }

  set {
    name  = "aws.defaultInstanceProfile"
    value = aws_iam_instance_profile.karpenter.name
  }

  depends_on = [
    module.eks,
    module.karpenter_irsa,
    aws_iam_instance_profile.karpenter,
    aws_iam_role.ec2_spot_fleet_tagging_role,
    aws_iam_role_policy_attachment.ec2_spot_fleet_tagging,
  ]
}

module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 4.17"

  role_name                          = "karpenter-controller-${var.namespace}"
  attach_karpenter_controller_policy = true

  karpenter_controller_cluster_id = module.eks.cluster_id
  karpenter_controller_node_iam_role_arns = [
    module.eks.eks_managed_node_groups["karpenter"].iam_role_arn
  ]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
}

resource "random_pet" "this" {
  length = 2
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile-${var.namespace}-${random_pet.this.id}"
  role = module.eks.eks_managed_node_groups["karpenter"].iam_role_name
}


# mcdaniel TO-DO: revisit the cpu resource limit, and perhaps add a memory limit
resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = <<-YAML
  apiVersion: karpenter.sh/v1alpha5
  kind: Provisioner
  metadata:
    name: default
  spec:
    #requirements:
    #  - key: karpenter.sh/capacity-type
    #    operator: In
    #    values: ["spot", "on-demand"]
    limits:
      resources:
        cpu: "400"        # 100 * 4 cpu
        memory: 1600Gi    # 100 * 16Gi
    provider:
      subnetSelector:
        karpenter.sh/discovery: ${var.namespace}
      securityGroupSelector:
        karpenter.sh/discovery: ${var.namespace}
      tags:
        karpenter.sh/discovery: ${var.namespace}

    # If nil, the feature is disabled, nodes will never expire
    ttlSecondsUntilExpired: 86400        # 1 Day = 60 seconds * 60 minutes * 24 hours;

    # If nil, the feature is disabled, nodes will never scale down due to low utilization
    ttlSecondsAfterEmpty: 1800          # 30 minutes = 60 seconds * 30 minutes
  YAML

  depends_on = [
    module.eks,
    helm_release.karpenter
  ]
}

resource "aws_iam_role" "ec2_spot_fleet_tagging_role" {
  name = "AmazonEC2SpotFleetTaggingRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "spotfleet.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ec2_spot_fleet_tagging" {
  role       = aws_iam_role.ec2_spot_fleet_tagging_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}
