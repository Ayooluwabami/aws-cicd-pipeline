# Observability

Three pillars, all wired end to end:

| Pillar | Produced by | Shipped by | Viewed in |
|---|---|---|---|
| Metrics | `prom-client` histogram + defaults at `GET /metrics`; EC2/agent system metrics | CloudWatch agent / CloudWatch | CloudWatch Metrics (`AwsCicdDemo`, `AWS/EC2`, `CWAgent`) |
| Logs | Structured JSON access log per request (`time`, `level`, `method`, `path`, `status`, `ms`) | CloudWatch agent tails pm2 logs → `/aws-cicd/app` | CloudWatch Logs Insights |
| Traces | X-Ray SDK Express middleware (one segment per request, `ENABLE_XRAY=true`) | X-Ray daemon (UDP :2000) → X-Ray API | X-Ray console: service map + traces |

Failure philosophy: observability is installed by `scripts/setup_monitoring.sh`
as a non-fatal deployment step. A broken agent degrades visibility; it never
blocks a release.

## Alerting

| Alarm | Source | Fires when |
|---|---|---|
| `<stack>-high-error-rate` | metric filter `{ $.status >= 500 }` on `/aws-cicd/app` | ≥ 5 HTTP 5xx in 5 min → see `docs/runbooks/high-error-rate.md` |
| `<stack>-instance-status-failed` | AWS/EC2 status checks | 2 consecutive failed checks |
| `<stack>-cpu-high` | AWS/EC2 CPUUtilization | > 85% for 15 min |
| `<stack>-pipeline-failed` | EventBridge | any pipeline execution fails |

All alarms publish to the stack's SNS topic (optional email subscription).

## Useful Logs Insights queries

Run against log group `/aws-cicd/app`:

```
# Error rate per 5 minutes
stats count(*) as requests, sum(status >= 500) as errors by bin(5m)

# p50 / p95 / p99 latency per 5 minutes
stats pct(ms, 50) as p50, pct(ms, 95) as p95, pct(ms, 99) as p99 by bin(5m)

# Slowest requests in the window
fields time, method, path, status, ms | sort ms desc | limit 20

# Traffic by path
stats count(*) as hits by path | sort hits desc
```

## Verifying traces

```bash
# On the instance
systemctl status xray
# In the AWS console: X-Ray → Service map should show aws-cicd-sample-app
# after a few requests hit the app.
```
