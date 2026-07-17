#!/bin/bash
# ApplicationStart hook — start the app under pm2 as the unprivileged
# ec2-user (never root) and persist across reboots.
set -eu

runuser -l ec2-user -c '
  cd /var/www/aws-cicd-app/app &&
  PORT=3000 NODE_ENV=production ENABLE_XRAY=true pm2 start dist/server.js --name aws-cicd-app --update-env &&
  pm2 save
'

echo "Application started on port 3000 as ec2-user."
