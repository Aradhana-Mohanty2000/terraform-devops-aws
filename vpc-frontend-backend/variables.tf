variable "aws_region" {
  default = "us-east-2"
}

variable "availability_zone" {
  default = "us-east-2a"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  default = "10.0.2.0/24"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0741dc526e1106ae5"
}

variable "key_name" {
  description = "AWS Key Pair Name (must already exist in your AWS account)"
}
