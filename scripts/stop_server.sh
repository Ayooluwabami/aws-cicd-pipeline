#!/bin/bash
# ApplicationStop hook — stop the running app if it exists.
# Must not fail on first deployment (when nothing is running yet).
set -u

if command -v pm2 >/dev/null 2>&1; then
  runuser -l ec2-user -c 'pm2 stop aws-cicd-app; pm2 delete aws-cicd-app' >/dev/null 2>&1 || true
  echo "Stopped existing app (if any)."
else
  echo "pm2 not installed yet — nothing to stop."
fi

exit 0
