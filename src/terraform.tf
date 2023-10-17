terraform {
  // import provider
  // doc: https://developer.hashicorp.com/terraform/language/providers/requirements
  required_providers {
    // doc: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.7.0"
    }

    // doc: https://registry.terraform.io/providers/hashicorp/random/latest/docs
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }

    // doc: https://registry.terraform.io/providers/hashicorp/tls/latest/docs
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.4"
    }
  }
  required_version = "~> 1.3"
}

