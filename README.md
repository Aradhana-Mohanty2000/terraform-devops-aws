# Terraform AWS DevOps Lab
 
A hands-on Terraform repository covering AWS infrastructure provisioning: EC2 public/private networking, an event-driven serverless pipeline (S3 → SQS → Lambda), and a custom VPC with a public frontend and private backend.
 
---
 
## Learning Objectives
 
* Installing Terraform and AWS CLI on an Amazon Linux EC2 instance
* Creating a dedicated, non-root `terraform` system user with sudo access
* Configuring AWS CLI credentials for programmatic access
* Core Terraform workflow: `init`, `validate`, `plan`, `apply`, `destroy`
* Writing HCL (HashiCorp Configuration Language) for AWS resources
* Provisioning an EC2 instance and toggling its public IP exposure
* Building an event-driven serverless pipeline using S3, SQS, and Lambda
* Using Terraform's `archive_file` data source to package Lambda code automatically
* IAM roles and least-privilege policies for Lambda execution
* Designing a custom VPC with public and private subnets
* Internet Gateway vs NAT Gateway — when each is needed and why
* Route tables and route table associations
* Writing reusable Terraform **modules** (vpc, security-group, ec2)
* Bootstrapping EC2 instances with `user_data` (Apache HTTPD, MongoDB)
* Security group design for network isolation (public-facing vs internal-only)
* Managing project state safely with `.gitignore` (excluding `.terraform/`, `*.tfstate`, provider binaries)
* Authenticating Git pushes to GitHub using SSH keys
* Reading CloudWatch Logs to verify Lambda execution
* Debugging real-world Terraform/AWS errors: region mismatches, key pair scoping, instance type eligibility
---
 
## Repository Structure
 
```text
terraform-devops-aws/
│
├── README.md
├── .gitignore
│
├── ec2-public-private-ip/
│   └── main.tf
│
├── s3-sqs-lambda/
│   ├── provider.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── main.tf
│   ├── output.tf
│   └── lambda/
│       └── index.py
│
└── vpc-frontend-backend/
    ├── provider.tf
    ├── variables.tf
    ├── terraform.tfvars
    ├── main.tf
    ├── outputs.tf
    ├── .gitignore
    ├── scripts/
    │   ├── frontend.sh
    │   └── backend.sh
    └── modules/
        ├── vpc/
        │   ├── main.tf
        │   ├── variables.tf
        │   └── outputs.tf
        ├── security-group/
        │   ├── main.tf
        │   ├── variables.tf
        │   └── outputs.tf
        └── ec2/
            ├── main.tf
            ├── variables.tf
            └── outputs.tf
```
 
---
 
## Prerequisites
 
* AWS account with an IAM user that has programmatic access
* Amazon Linux 2023 EC2 instance
* Terraform installed
* AWS CLI installed and configured
* Git installed, with an SSH key added to your GitHub account
* An EC2 key pair created **in the same region** you intend to deploy into
---
 
# 1. Installation Process
 
## 1.1 Install Terraform
 
```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform
terraform version
```
 
## 1.2 Create a Dedicated Terraform User
 
```bash
sudo useradd -m -s /bin/bash terraform
echo "terraform ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/terraform
sudo chmod 440 /etc/sudoers.d/terraform
sudo visudo -c
sudo su - terraform
```
 
Note the `-` after `su` — this opens a full login shell as the `terraform` user, correctly landing in `/home/terraform`. Without the dash, the shell context can behave inconsistently.
 
## 1.3 Install and Configure AWS CLI
 
```bash
sudo dnf install -y awscli
aws --version
aws configure
```
 
`aws configure` prompts for:
* AWS Access Key ID
* AWS Secret Access Key
* Default region
* Default output format (`json`)
Verify:
```bash
aws sts get-caller-identity
```
 
## 1.4 Set Up Git + SSH Authentication
 
GitHub no longer accepts account passwords for `git push` over HTTPS — use SSH keys instead.
 
```bash
ssh-keygen -t ed25519 -C "your-label-here"
cat ~/.ssh/id_ed25519.pub
```
 
Copy the printed key, then in GitHub: **Settings → SSH and GPG keys → New SSH key** → paste it.
 
Set git identity (required once per fresh machine/user, otherwise commits fail with "Author identity unknown"):
```bash
git config --global user.email "your-email@example.com"
git config --global user.name "Your Name"
```
 
Clone or set the remote:
```bash
git clone git@github.com:YOUR-USERNAME/YOUR-REPO.git
# or, if already cloned via HTTPS:
git remote set-url origin git@github.com:YOUR-USERNAME/YOUR-REPO.git
ssh -T git@github.com
```
 
---
 
# 2. Core Terraform Workflow
 
| Command | Purpose |
|---|---|
| `terraform init` | Downloads required providers, initializes the working directory |
| `terraform validate` | Checks `.tf` syntax for correctness |
| `terraform plan` | Shows what Terraform *will* do, without making changes |
| `terraform apply` | Creates/updates the actual AWS resources |
| `terraform destroy` | Tears down all resources managed by the configuration |
 
Always run these commands from inside the specific project folder containing the relevant `.tf` files. **Each folder has its own independent state** — `terraform destroy` in one folder only affects resources that folder created, and has no awareness of other folders or manually-created resources.
 
---
 
# 3. Task 1 — EC2 Instance With a Public IP
 
**Folder:** `ec2-public-private-ip/main.tf`
 
```hcl
provider "aws" {
  region = "ap-south-1"
}
 
resource "aws_instance" "web" {
  ami                          = "ami-0e38835daf6b8a2b9"
  instance_type                = "t3.micro"
  associate_public_ip_address  = true
 
  tags = {
    Name = "public-server"
  }
}
```
 
```bash
cd ec2-public-private-ip
terraform init
terraform validate
terraform plan
terraform apply
```
 
**Verification:** EC2 console shows a Public IPv4 address on the instance.
 
---
 
# 4. Task 2 — Convert the Instance to Private
 
Edit the same file, changing only one line:
 
```hcl
associate_public_ip_address = false
```
 
```bash
terraform apply
```
 
Terraform destroys and recreates the instance. **Verification:** EC2 console shows no Public IPv4 address.
 
---
 
# 5. Task 3 — S3 → SQS → Lambda Event Pipeline
 
**Goal:** when a file is uploaded to an S3 bucket, an event notification is sent to an SQS queue, which triggers a Lambda function that prints the uploaded file's name to CloudWatch Logs.
 
**Folder:** `s3-sqs-lambda/`
 
## Architecture
 
```text
   Upload file
       │
       ▼
 ┌───────────┐  event notification  ┌───────────┐   triggers   ┌──────────┐
 │ S3 Bucket │ ─────────────────────▶│ SQS Queue │ ─────────────▶│  Lambda  │
 └───────────┘                       └───────────┘               └────┬─────┘
                                                                        │
                                                                        ▼
                                                              CloudWatch Logs
                                                     "New object uploaded ->
                                                      Bucket: ..., File: ..."
```
 
## main.tf (combined for brevity — see repo for full file split)
 
```hcl
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
}
 
resource "aws_sqs_queue" "this" {
  name = var.queue_name
}
 
resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id
 
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowS3ToSendMessage"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.this.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.this.arn
          }
        }
      }
    ]
  })
}
 
resource "aws_s3_bucket_notification" "this" {
  bucket = aws_s3_bucket.this.id
 
  queue {
    queue_arn = aws_sqs_queue.this.arn
    events    = ["s3:ObjectCreated:*"]
  }
 
  depends_on = [aws_sqs_queue_policy.this]
}
 
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/lambda/index.zip"
}
 
resource "aws_iam_role" "lambda_role" {
  name = "${var.lambda_function_name}-role"
 
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}
 
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.lambda_function_name}-policy"
  role = aws_iam_role.lambda_role.id
 
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.this.arn
      }
    ]
  })
}
 
resource "aws_lambda_function" "this" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 10
}
 
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.this.arn
  function_name    = aws_lambda_function.this.arn
  batch_size       = 1
}
```
 
## lambda/index.py
 
```python
import json
 
 
def handler(event, context):
    for record in event.get("Records", []):
        body = json.loads(record["body"])
        for s3_record in body.get("Records", []):
            bucket = s3_record["s3"]["bucket"]["name"]
            key = s3_record["s3"]["object"]["key"]
            print(f"New object uploaded -> Bucket: {bucket}, File: {key}")
 
    return {"statusCode": 200}
```
 
## Deploy and Test
 
```bash
cd s3-sqs-lambda
terraform init
terraform validate
terraform plan
terraform apply
 
echo "hello world" > test.txt
aws s3 cp test.txt s3://YOUR-BUCKET-NAME/
aws logs tail /aws/lambda/s3-object-logger --since 5m
```
 
Expected log output:
```text
New object uploaded -> Bucket: itwsit-s3-lambda-9284, File: test.txt
```
 
---
 
# 6. Task 4 — Custom VPC With Frontend (Apache) and Backend (MongoDB)
 
**Goal:** build a VPC with public and private subnets, an Internet Gateway, a NAT Gateway, route tables, a frontend EC2 instance with a public IP running Apache HTTPD, and a backend EC2 instance with no public IP running MongoDB — with the frontend able to reach the backend, while the backend stays inaccessible from the internet.
 
**Folder:** `vpc-frontend-backend/`
 
## Architecture
 
```text
                    Internet
                       │
                       ▼
              ┌─────────────────┐
              │ Internet Gateway│
              └────────┬────────┘
                       │
        ┌──────────────┴───────────────┐
        │           VPC (10.0.0.0/16)   │
        │                                │
        │  ┌──────────────┐              │
        │  │ Public Subnet │              │
        │  │ 10.0.1.0/24   │              │
        │  │               │              │
        │  │ Frontend EC2  │              │
        │  │ (Apache)      │◄── public IP │
        │  │               │              │
        │  │ NAT Gateway   │              │
        │  └───────┬───────┘              │
        │          │ (private route)      │
        │  ┌───────▼───────┐              │
        │  │ Private Subnet│              │
        │  │ 10.0.2.0/24   │              │
        │  │               │              │
        │  │ Backend EC2   │              │
        │  │ (MongoDB)     │◄── NO public │
        │  │ port 27017    │     IP       │
        │  └───────────────┘              │
        └────────────────────────────────┘
```
 
The frontend security group allows HTTP and SSH from the internet. The backend security group only accepts traffic on port 27017 (MongoDB) and SSH from the **frontend's security group** — nothing from the public internet. The backend still gets outbound internet access via the NAT Gateway, needed for installing packages.
 
## Module structure
 
This project is broken into three reusable modules:
 
* **`modules/vpc`** — VPC, public + private subnets, Internet Gateway, NAT Gateway + Elastic IP, public and private route tables, route table associations
* **`modules/security-group`** — frontend SG (public HTTP/SSH) and backend SG (MongoDB + SSH, restricted to the frontend SG only)
* **`modules/ec2`** — a generalized EC2 module reused for both the frontend and backend instance, parameterized by subnet, security group, public-IP toggle, and `user_data` script
## modules/vpc/main.tf
 
```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
 
  tags = { Name = "student-vpc" }
}
 
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true
 
  tags = { Name = "public-subnet" }
}
 
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
 
  tags = { Name = "private-subnet" }
}
 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "student-igw" }
}
 
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "nat-eip" }
}
 
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "student-nat-gw" }
  depends_on    = [aws_internet_gateway.igw]
}
 
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
 
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
 
  tags = { Name = "public-route-table" }
}
 
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
 
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
 
  tags = { Name = "private-route-table" }
}
 
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}
 
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}
```
 
## modules/security-group/main.tf
 
```hcl
resource "aws_security_group" "frontend" {
  name        = "frontend-sg"
  description = "Allow HTTP and SSH from the internet"
  vpc_id      = var.vpc_id
 
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  tags = { Name = "frontend-sg" }
}
 
resource "aws_security_group" "backend" {
  name        = "backend-sg"
  description = "Allow MongoDB and SSH only from the frontend security group"
  vpc_id      = var.vpc_id
 
  ingress {
    description     = "MongoDB from frontend only"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }
 
  ingress {
    description     = "SSH from frontend only (acts as bastion)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }
 
  egress {
    description = "Allow outbound so backend can reach NAT Gateway for updates"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  tags = { Name = "backend-sg" }
}
```
 
## modules/ec2/main.tf
 
```hcl
resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group]
  associate_public_ip_address = var.associate_public_ip
  key_name                    = var.key_name
  user_data                   = var.user_data
 
  tags = { Name = var.instance_name }
}
```
 
## scripts/frontend.sh
 
```bash
#!/bin/bash
dnf update -y
dnf install -y httpd
 
systemctl enable httpd
systemctl start httpd
 
echo "<h1>Frontend Server - Apache HTTPD</h1>" > /var/www/html/index.html
```
 
## scripts/backend.sh
 
```bash
#!/bin/bash
cat > /etc/yum.repos.d/mongodb-org-7.0.repo << 'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
EOF
 
dnf install -y mongodb-org
 
sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
 
systemctl enable mongod
systemctl start mongod
```
 
## main.tf (root — wires the modules together)
 
```hcl
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
  source               = "./modules/ec2"
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
  source               = "./modules/ec2"
  ami_id               = var.ami_id
  instance_type        = var.instance_type
  subnet_id            = module.vpc.private_subnet_id
  security_group       = module.security_group.backend_sg_id
  key_name             = var.key_name
  associate_public_ip  = false
  instance_name        = "backend-mongodb"
  user_data            = file("${path.module}/scripts/backend.sh")
}
```
 
## Deploy
 
```bash
cd vpc-frontend-backend
nano terraform.tfvars   # set key_name to a real key pair that exists in your target region
terraform init
terraform validate
terraform plan
terraform apply
```
 
## Verification
 
1. **Frontend is publicly reachable:** open `http://FRONTEND_PUBLIC_IP` in a browser — confirm "Frontend Server - Apache HTTPD" loads.
2. **Backend has no public IP:** EC2 console → `backend-mongodb` → confirm Public IPv4 address is blank.
3. **Frontend can reach backend:** SSH into the frontend, then test the MongoDB port:
```bash
   sudo dnf install -y nmap-ncat
   nc -zv BACKEND_PRIVATE_IP 27017
```
   Expected: `Connected to <ip>:27017`.
 
---
 
# 7. .gitignore
 
These should never be committed — they contain large provider binaries or sensitive state data:
 
```text
.terraform/
*.tfstate
*.tfstate.*
.terraform.lock.hcl
```
 
---
 
# 8. Cleanup
 
Each project folder has its own independent state, so destroy each one separately when you're done testing:
 
```bash
cd vpc-frontend-backend && terraform destroy
 
cd ../s3-sqs-lambda && terraform destroy
 
cd ../ec2-public-private-ip && terraform destroy
```
 
`terraform destroy` only removes resources tracked in the **current folder's** state file — it cannot affect resources in other folders, or resources created manually outside of Terraform entirely. The NAT Gateway in particular has an hourly cost even when idle, so don't leave the VPC project running unnecessarily.
 
---
 
 
# Author
 
Aradhana Mohanty
GitHub: [Aradhana-Mohanty2000](https://github.com/Aradhana-Mohanty2000)
