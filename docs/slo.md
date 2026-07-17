# Service Level Objectives

**System:** aws-cicd-pipeline
**Last reviewed:** 2026-07-12

An SLO is a promise to users; the error budget is the enforcement mechanism.
Without them there is no objective way to decide whether feature work or
reliability work comes first. These are defined before the first deployment.

## SLIs and SLOs

| SLI | Target (SLO) | Measurement | Window |
|---|---|---|---|
| Availability — `/api/health` returns 200 | 99.5% | CloudWatch Synthetics canary or external uptime check against `http://<host>:3000/api/health` | 30-day rolling |
| Latency p99 | < 300 ms | ALB/target metrics in production; `curl -w '%{time_total}'` sampling for the demo | 5-min rolling |
| Deployment freshness — push to healthy | < 10 min | pipeline execution start vs ValidateService success timestamp | per deployment |
| Pipeline success rate | ≥ 90% | failed executions / total executions (CodePipeline console) | 7-day rolling |
| Change failure rate | < 15% | deployments that triggered rollback / total deployments | 30-day rolling |

> 99.5% (not 99.9%) reflects a single t3.micro in one AZ with no load balancer.
> A production topology (ASG + ALB, multi-AZ) would target 99.9%+.

## Error budget

| SLO | Allowed failure | Monthly budget |
|---|---|---|
| 99.5% availability | 0.5% | 3h 39m downtime |
| ≥ 90% pipeline success | 10% of runs | roughly 3 failed runs/month at daily deploy cadence |

### Error budget policy

- **50% consumed:** engineering lead notified; risky merges need a second review.
- **100% consumed:** feature freeze. All effort moves to reliability. Postmortem
  (see `incident-postmortem-template.md`) required within 48 hours, and no new
  deployments until the root cause has a fix in place.

## Alerting hooks

- Pipeline failure → EventBridge → SNS (`<stack>-pipeline-alerts`).
- HTTP 5xx rate (≥ 5 in 5 min, from the structured access log metric filter) → CloudWatch alarm → same SNS topic.
- Instance status check failure → CloudWatch alarm → same SNS topic.
- Sustained CPU > 85% (15 min) → CloudWatch alarm → same SNS topic.

Error-rate and latency SLIs are measured from the structured access logs
(Logs Insights queries in `monitoring/README.md`) and the `prom-client`
histogram at `/metrics`; per-request breakdowns come from X-Ray traces.
The app also self-reports live SLIs against these targets at `GET /api/sli`
(rolling window over recent requests), which the status page displays.
The targets are mirrored in `app/src/app.ts` (`SLO_TARGETS`); change both
together.
