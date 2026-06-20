# Terraform AWS DevOps Lab
 
A hands-on Terraform repository covering AWS infrastructure provisioning, EC2 public/private networking, and an event-driven serverless pipeline (S3 → SQS → Lambda).
 
---
 
## Learning Objectives 
 
By the end of this session, the following concepts were covered:
 
* Installing Terraform and AWS CLI on an Amazon Linux EC2 instance
* Creating a dedicated, non-root `terraform` system user with sudo access
* Configuring AWS CLI credentials for programmatic access
* Core Terraform workflow: `init`, `validate`, `plan`, `apply`, `destroy`
* Writing HCL (HashiCorp Configuration Language) for AWS resources
* Provisioning an EC2 instance and toggling its public IP exposure
* Building an event-driven serverless pipeline using S3, SQS, and Lambda
* Using Terraform's `archive_file` data source to package Lambda code automatically
* IAM roles and least-privilege policies for Lambda execution
* Managing project state safely with `.gitignore` (excluding `.terraform/`, `*.tfstate`, provider binaries)
* Authenticating Git pushes to GitHub using SSH keys (after working through HTTPS token issues)
* Reading CloudWatch Logs to verify Lambda execution
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
└── s3-sqs-lambda/
    ├── provider.tf
    ├── variables.tf
    ├── terraform.tfvars
    ├── main.tf
    ├── output.tf
    └── lambda/
        └── index.py
```
 
---
 
## Prerequisites
 
* AWS account with an IAM user that has programmatic access
* Amazon Linux 2023 EC2 instance
* Terraform installed
* AWS CLI installed and configured
* Git installed, with an SSH key added to your GitHub account
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
 
Running Terraform as `root` isn't best practice. Create a separate user instead:
 
```bash
sudo useradd -m -s /bin/bash terraform
echo "terraform ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/terraform
sudo chmod 440 /etc/sudoers.d/terraform
sudo visudo -c
sudo su - terraform
```
 
## 1.3 Install and Configure AWS CLI
 
```bash
sudo dnf install -y awscli
aws --version
aws configure
```
 
`aws configure` prompts for:
* AWS Access Key ID
* AWS Secret Access Key
* Default region (e.g. `ap-south-1`)
* Default output format (`json`)
Verify credentials:
 
```bash
aws sts get-caller-identity
```
 
## 1.4 Set Up Git + SSH Authentication
 
GitHub no longer accepts account passwords for `git push` over HTTPS, so SSH keys are used instead.
 
```bash
ssh-keygen -t ed25519 -C "your-label-here"
cat ~/.ssh/id_ed25519.pub
```
 
Copy the printed public key, then in GitHub: **Settings → SSH and GPG keys → New SSH key** → paste it.
 
Set your repo's remote to use SSH instead of HTTPS:
 
```bash
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
 
Always run these commands from inside the specific project folder containing the relevant `.tf` files.
 
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
 
**Verification:** Check the EC2 console — the instance should display a Public IPv4 address.
 
---
 
# 4. Task 2 — Convert the Instance to Private
 
Edit the same file, changing only one line:
 
```hcl
associate_public_ip_address = false
```
 
```bash
terraform apply
```
 
Terraform destroys and recreates the instance. **Verification:** the EC2 console should now show no Public IPv4 address — the instance is only reachable via private networking (e.g. a bastion host, VPN, or Session Manager).
 
---
 
# 5. Task 3 — S3 → SQS → Lambda Event Pipeline
 
**Goal:** when a file is uploaded to an S3 bucket, an event notification is sent to an SQS queue, which triggers a Lambda function that prints the uploaded file's name to CloudWatch Logs.
 
**Folder:** `s3-sqs-lambda/`
 
## Architecture
 
```text
   Upload file
       │
       ▼
 ┌───────────┐     event notification     ┌───────────┐     triggers     ┌───────────┐
 │ S3 Bucket │ ───────────────────────────▶│ SQS Queue │ ────────────────▶│  Lambda   │
 └───────────┘                              └───────────┘                  └───────────┘
                                                                                  │
                                                                                  ▼
                                                                         CloudWatch Logs
                                                                     "New object uploaded ->
                                                                      Bucket: ..., File: ..."
```
 
## provider.tf
 
```hcl
terraform {
  required_version = ">= 1.0"
 
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}
 
provider "aws" {
  region = var.aws_region
}
```
 
## variables.tf
 
```hcl
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-south-1"
}
 
variable "bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
}
 
variable "queue_name" {
  description = "SQS queue name"
  type        = string
  default     = "s3-event-queue"
}
 
variable "lambda_function_name" {
  description = "Lambda function name"
  type        = string
  default     = "s3-object-logger"
}
```
 
## terraform.tfvars
 
```hcl
aws_region           = "ap-south-1"
bucket_name          = "itwsit-s3-lambda-9284"
queue_name           = "s3-event-queue"
lambda_function_name = "s3-object-logger"
```
 
## main.tf
 
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
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
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
 
## output.tf
 
```hcl
output "bucket_name" {
  value = aws_s3_bucket.this.id
}
 
output "queue_url" {
  value = aws_sqs_queue.this.id
}
 
output "lambda_function_name" {
  value = aws_lambda_function.this.function_name
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
 
## Deploy
 
```bash
cd s3-sqs-lambda
terraform init
terraform validate
terraform plan
terraform apply
```
 
## Test
 
```bash
echo "hello world" > test.txt
aws s3 cp test.txt s3://YOUR-BUCKET-NAME/
```
 
Wait 15–20 seconds, then check CloudWatch Logs:
 
```bash
aws logs tail /aws/lambda/s3-object-logger --since 5m
```
 
Expected output:
 
```text
New object uploaded -> Bucket: itwsit-s3-lambda-9284, File: test.txt
```
 
---
 
# 6. .gitignore
 
These files should never be committed — they contain large provider binaries or sensitive state data:
 
```text
.terraform/
*.tfstate
*.tfstate.*
.terraform.lock.hcl
```
 
---
 
# 7. Cleanup
 
To avoid ongoing AWS charges after testing, destroy resources in each folder:
 
```bash
cd s3-sqs-lambda
terraform destroy
 
cd ../ec2-public-private-ip
terraform destroy
```
 
---
 
# 8. Key Troubleshooting Notes 
 
* `terraform init` reporting "empty directory" almost always means either the file extension was wrong (`.txt` instead of `.tf`), or the command was run from the wrong folder/user's home directory.
* GitHub blocks pushes containing any file over 100 MB — committing the `.terraform/` provider binaries by accident will cause a `pre-receive hook declined` error. Fix by adding `.gitignore` *before* the first commit, or by resetting git history if it's already baked in.
* GitHub no longer accepts account passwords for HTTPS git operations — use either a Personal Access Token (classic, with the `repo` scope) or, more reliably, SSH key authentication.
* Never paste tokens or passwords into a chat or anywhere outside the terminal prompt that's asking for them — if a token is ever exposed, revoke it immediately and generate a new one.
---
 
# Author
 
Aradhana Mohanty
GitHub: [Aradhana-Mohanty2000](https://github.com/Aradhana-Mohanty2000)
