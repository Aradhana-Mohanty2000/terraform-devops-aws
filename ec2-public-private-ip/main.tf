provider "aws" {
  region = "ap-south-1"
}

resource "aws_instance" "web" {
  ami                          = "ami-0e38835daf6b8a2b9"
  instance_type                = "t3.micro"
  associate_public_ip_address  = false

  tags = {
    Name = "public-server"
  }
}
