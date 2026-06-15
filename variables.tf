variable "aws_region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "eks-datadog-lab"
}

variable "dd_api_key" {
  description = "Datadog API Key"
  sensitive   = true
}
