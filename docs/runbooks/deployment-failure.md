# Runbook: CodeDeploy deployment failure

**Alert:** Deploy stage red in CodePipeline, or CodeDeploy deployment marked Failed.
**Severity:** P2 if rollback succeeded (old version still serving); P1 if the app is down.
**SLO impact:** availability (if down) and change failure rate.

## Step 1 — identify the failed lifecycle event

CodeDeploy console → Deployments → failed deployment → **View events**.
Each hook maps to a script in `scripts/`:

| Lifecycle event | Script | Common cause |
|---|---|---|
| ApplicationStop | `stop_server.sh` | stale pm2 state from a broken earlier revision |
| BeforeInstall | `before_install.sh` | Node/pm2 install failed (no outbound network?) |
| AfterInstall | `install_dependencies.sh` | `npm ci` failed on the instance |
| ApplicationStart | `start_server.sh` | pm2 couldn't start the app as ec2-user |
| ValidateService | `validate_service.sh` | app started but `/api/health` never returned 200 |

## Step 2 — inspect the instance

```bash
# Session Manager (no SSH key needed) or ssh ec2-user@<ip>
sudo systemctl status codedeploy-agent
sudo tail -100 /var/log/aws/codedeploy-agent/codedeploy-agent.log
sudo tail -100 /opt/codedeploy-agent/deployment-root/deployment-logs/codedeploy-agent-deployments.log
runuser -l ec2-user -c 'pm2 status && pm2 logs aws-cicd-app --lines 50 --nostream'
curl -s http://127.0.0.1:3000/api/health
```

## Step 3 — common fixes

- **Agent not running:** `sudo systemctl restart codedeploy-agent`, then retry the deployment.
- **AccessDenied pulling the bundle:** instance role lost S3 read on the artifact bucket — check the stack's `Ec2InstanceRole`.
- **ApplicationStop fails repeatedly:** a cached broken revision. Clear it:
  `sudo rm -rf /opt/codedeploy-agent/deployment-root/*` and redeploy.
- **Health check fails:** `pm2 logs` shows the crash. Typical: missing production
  dependency (check `install_dependencies.sh` output) or port 3000 already bound.

## Step 4 — rollback state

Auto-rollback is enabled: a failed deployment redeploys the last known-good
revision automatically. Confirm the app serves the **old** commit SHA and status
**IN SERVICE** while you fix forward. Never disable the ValidateService gate to
force a deploy through.

## Verify recovery

Re-run the Deploy stage (Retry) or push the fix. All lifecycle events green,
`/api/health` returns 200, and the page shows the expected commit.
