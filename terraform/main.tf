terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"

}
data "aws_caller_identity" "current" {}
output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
resource "aws_iam_policy" "policy" {
  name        = "demopolicy1234"
  description = "My test policy"

  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
    ]
}
EOT
}
resource "aws_iam_role" "role" {
  name = "demorole1234"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy.arn
}
resource "aws_iam_instance_profile" "profile" {
  name = "deployment"
  role = aws_iam_role.role.name
}

resource "aws_instance" "web" {
  ami           = "ami-0f34c5ae932e6f0e4"
  instance_type = "t2.micro"
 key_name = "fdec.pem"
vpc_security_group_ids = [aws_security_group.unique.id]
  user_data = <<EOF
#!/bin/bash
BUCKET=cloud-11
sudo dnf install java-11-amazon-corretto -y
wget https://dlcdn.apache.org/tomcat/tomcat-8/v8.5.91/bin/apache-tomcat-8.5.91.zip
sudo unzip apache-tomcat-8.5.91.zip
sudo mv apache-tomcat-8.5.91 /mnt/tomcat
KEY=`aws s3 ls cloud-11 --recursive | sort | tail -n 1 | awk '{print $4}'`
aws s3 cp s3://$BUCKET/$KEY /mnt/tomcat/webapps/
sudo chmod 0755 /mnt/tomcat/bin/*
sudo /mnt/tomcat/bin/catalina.sh start
EOF
}
resource "aws_security_group" "unique" {
name_prefix = "terraform-sg-"
ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
                                
