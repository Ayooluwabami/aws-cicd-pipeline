#!/bin/bash
# AfterInstall hook — install production dependencies, then hand the
# deployment directory to the unprivileged runtime user.
set -eu

cd /var/www/aws-cicd-app/app
echo "Installing production dependencies..."
npm ci --omit=dev

chown -R ec2-user:ec2-user /var/www/aws-cicd-app

echo "AfterInstall complete."
