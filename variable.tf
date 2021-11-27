variable "env"{
  type = string
  default = "homolog"
}


variable "cidr_block"{
  type = string
  description = "VPC cidr"
  default = "10.0.0.0/16"
}

variable "private_subnets" {
  type = map
  description = "private_subnets"
  default = {
    "sa-east-1a" = "10.0.0.0/24"
    "sa-east-1b" = "10.0.1.0/24"
  }
}

variable "public_subnets" {
  type = map
  description = "public_subnets"
  default = {
    "sa-east-1a" = "10.0.2.0/24"
    "sa-east-1b" = "10.0.3.0/24"
  }
}