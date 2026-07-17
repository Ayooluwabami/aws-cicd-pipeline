#!/bin/bash
# EC2 user data — paste into "Advanced details → User data" when launching
# the instance (Amazon Linux 2023). Installs and starts the CodeDeploy agent.
set -eu

dnf update -y
dnf install -y ruby wget

# CodeDeploy agent installer is served per-region from S3.
# Change 'us-east-1' below if your instances run in a different region.
REGION="us-east-1"
cd /home/ec2-user
wget "https://aws-codedeploy-${REGION}.s3.${REGION}.amazonaws.com/latest/install"
chmod +x ./install
./install auto

systemctl enable codedeploy-agent
systemctl start codedeploy-agent
