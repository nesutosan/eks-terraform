// doc: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
provider "aws" {
  region = var.region
}

// Filter out local zones, which are not currently supported 
// with managed node groups
// doc: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

// Create cluster name in local with Random Provider
resource "random_string" "suffix" {
  length  = 8
  special = false
}
// manage local resources
// doc: https://registry.terraform.io/providers/hashicorp/local/latest
locals {
  cluster_name = "nesutosan-eks-${random_string.suffix.result}"
}


// Use module terraform-aws-modules/vpc/aws to configure vpc
// doc: https://github.com/terraform-aws-modules/terraform-aws-vpc
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "eks-vpc"

  // The IPv4 CIDR block for the VPC.
  cidr = "172.32.0.0/16"
  // A list of availability zones names or ids in the region
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["172.32.1.0/24", "172.32.2.0/24", "172.32.3.0/24"]
  public_subnets  = ["172.32.4.0/24", "172.32.5.0/24", "172.32.6.0/24"]

  // Provision NAT Gateways for each of your private networks.
  enable_nat_gateway   = true
  // Provision a single shared NAT Gateway across all of your private networks.
  single_nat_gateway   = true
  one_nat_gateway_per_az = false
  // Enable DNS hostnames in the VPC.
  enable_dns_hostnames = true

  // Additional tags for the public subnets.
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  // Additional tags for the private subnets.
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
}

// Use module terraform-aws-modules/eks/aws
// doc: https://github.com/terraform-aws-modules/terraform-aws-eks
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.3"

  cluster_name    = local.cluster_name
  cluster_version = "1.27"

  // get vpc_id, private_subnets from output of vpc module
  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets

  // Indicates the Amazon EKS public API server endpoint is enabled
  cluster_endpoint_public_access = true

  // Map of EKS managed node group default configurations
  eks_managed_node_group_defaults = {
    // Amazon Linux 2 (x86-64)
    // doc: https://docs.aws.amazon.com/cdk/api/v2/python/aws_cdk.aws_eks/NodegroupAmiType.html
    ami_type = "AL2_x86_64"
  }

  // Map of EKS managed node group definitions to create
  eks_managed_node_groups = {
    one = {
      name = "node-group-1"
      // for test only
      instance_types = ["t2.micro"]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }

    two = {
      name = "node-group-2"
      // for test only
      instance_types = ["t2.micro"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
}


// https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/ 
// doc: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

// aws-ebs-csi-driver submodules of module fully-loaded-eks-cluster
/* docs: [https://registry.terraform.io/modules/bootlabstech/fully-loaded-eks-cluster/aws/latest/submodules/aws-ebs-csi-driver, 
https://github.com/bootlabstech/terraform-aws-fully-loaded-eks-cluster/tree/v1.0.7/modules/kubernetes-addons/aws-ebs-csi-driver] */
// Creates single IAM role which can be assumed by trusted resources using OpenID Connect Federated Users.
module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.7.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

// Resource: aws_eks_addon
// doc: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon
// Attaching persistent storage to an EKS cluster by using aws-ebs-csi-driver.
resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.20.0-eksbuild.1"
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
}