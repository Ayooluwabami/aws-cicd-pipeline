#!/bin/bash
# AfterInstall hook (second action) — point the CloudWatch agent at the
# app's structured logs. Non-fatal: a monitoring failure must never block
# a deployment; the pipeline-failure runbook covers degraded observability.
set -u

CONFIG=/var/www/aws-cicd-app/monitoring/cloudwatch-agent.json
CTL=/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl

if [ -x "$CTL" ] && [ -f "$CONFIG" ]; then
  if "$CTL" -a fetch-config -m ec2 -s -c "file:$CONFIG"; then
    echo "CloudWatch agent shipping app logs to /aws-cicd/app."
  else
    echo "WARN: CloudWatch agent config failed (non-fatal, deploy continues)."
  fi
else
  echo "WARN: CloudWatch agent not installed (non-fatal, deploy continues)."
fi

# X-Ray daemon: receives trace segments from the app over UDP :2000 and
# forwards them to the X-Ray API. Also non-fatal.
if ! systemctl is-active --quiet xray 2>/dev/null; then
  if ! command -v xray >/dev/null 2>&1 && [ ! -x /usr/bin/xray ]; then
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ]; then
      RPM="aws-xray-daemon-3.x.arm64.rpm"
    else
      RPM="aws-xray-daemon-3.x.rpm"
    fi
    echo "Installing X-Ray daemon (${RPM})..."
    curl -sSfL "https://s3.us-east-2.amazonaws.com/aws-xray-assets.us-east-2/xray-daemon/${RPM}" -o /tmp/xray.rpm \
      && dnf install -y /tmp/xray.rpm \
      || echo "WARN: X-Ray daemon install failed (non-fatal, deploy continues)."
  fi
  if [ -x /usr/bin/xray ] || command -v xray >/dev/null 2>&1; then
    systemctl enable xray >/dev/null 2>&1 || true
    systemctl start xray && echo "X-Ray daemon running." \
      || echo "WARN: X-Ray daemon failed to start (non-fatal, deploy continues)."
  fi
fi

exit 0
