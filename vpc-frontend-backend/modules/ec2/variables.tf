variable "ami_id" {}
variable "instance_type" {}
variable "subnet_id" {}
variable "security_group" {}
variable "key_name" {}
variable "instance_name" {}

variable "associate_public_ip" {
  default = true
}

variable "user_data" {
  default = ""
}
