# Runbook: high error rate

**Alert:** `<stack>-high-error-rate` (≥ 5 HTTP 5xx in 5 minutes, from the structured access log).
**Severity:** P1 if sustained (users are seeing failures); P2 if a brief spike that self-recovered.
**SLO impact:** error-rate SLO (< 1%) and possibly availability.

## Step 1 — scope it

CloudWatch Logs Insights on `/aws-cicd/app`:

```
fields time, method, path, status, ms
| filter status >= 500
| sort time desc
| limit 50
```

Questions to answer: one path or all paths? Constant or burst? Did it start
at a deployment time (check CodeDeploy → Deployments for a matching timestamp)?

## Step 2 — correlate

- **Started at a deploy:** the new revision is bad. Roll back: CodeDeploy →
  Deployments → redeploy the previous revision (or `git revert` + push and let
  the pipeline ship it). Fix forward only if the fix is trivial and tested.
- **No deploy correlation:** check the X-Ray trace for a failing request
  (X-Ray console → Traces, filter `responsetime > 1` or fault traces) to see
  which operation inside the request fails.
- **Resource pressure:** cross-check the CPU alarm and `pm2 logs` for
  out-of-memory restarts (`runuser -l ec2-user -c 'pm2 logs aws-cicd-app --lines 100 --nostream'`).

## Step 3 — mitigate

Restore service first, diagnose second: rollback beats debugging in
production. The health-gated deploy means a rollback is always one
known-good artifact away.

## Step 4 — close the loop

File a postmortem if the error budget took a visible hit
(`docs/incident-postmortem-template.md`). The action items should add a gate
or alarm that would have caught this class of failure earlier.
