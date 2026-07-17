#!/bin/bash
# BeforeInstall hook — prepare the instance for the new revision.
set -eu

# Install Node.js 20 if missing (Amazon Linux 2023)
if ! command -v node >/dev/null 2>&1; then
  echo "Installing Node.js 20..."
  curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
  dnf install -y nodejs
fi

# Install pm2 process manager if missing
if ! command -v pm2 >/dev/null 2>&1; then
  echo "Installing pm2..."
  npm install -g pm2
fi

# Install the CloudWatch agent if missing (log shipping; non-fatal)
if [ ! -x /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]; then
  dnf install -y amazon-cloudwatch-agent || echo "WARN: CloudWatch agent install failed (non-fatal)."
fi

# Clean the deployment directory so stale files never survive a deploy
rm -rf /var/www/aws-cicd-app
mkdir -p /var/www/aws-cicd-app

echo "BeforeInstall complete."
