module "vpc" {
  source = "./modules/vpc"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr   = var.public_subnet_cidr
  private_subnet_cidr  = var.private_subnet_cidr
  availability_zone    = var.availability_zone
}

module "security_group" {
  source = "./modules/security-group"

  vpc_id = module.vpc.vpc_id
}

module "frontend" {
  source = "./modules/ec2"

  ami_id               = var.ami_id
  instance_type        = var.instance_type
  subnet_id            = module.vpc.public_subnet_id
  security_group       = module.security_group.frontend_sg_id
  key_name             = var.key_name
  associate_public_ip  = true
  instance_name        = "frontend-apache"
  user_data            = file("${path.module}/scripts/frontend.sh")
}

module "backend" {
  source = "./modules/ec2"

  ami_id               = var.ami_id
  instance_type        = var.instance_type
  subnet_id            = module.vpc.private_subnet_id
  security_group       = module.security_group.backend_sg_id
  key_name             = var.key_name
  associate_public_ip  = false
  instance_name        = "backend-mongodb"
  user_data            = file("${path.module}/scripts/backend.sh")
}
