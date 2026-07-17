# Game day: proving the reliability machinery works

Run these exercises on the live stack after the first successful deployment.
Each one validates a specific SRE control. Record findings in a postmortem
(`incident-postmortem-template.md`) even when everything passes; "it worked"
with evidence is the deliverable.

## Exercise 1: process crash (self-healing)

**Hypothesis:** pm2 restarts a crashed app within seconds; the tick strip on
the status page shows at most a brief blip.

```bash
# on the instance
runuser -l ec2-user -c 'pm2 pid aws-cicd-app'
sudo kill -9 <pid>
runuser -l ec2-user -c 'pm2 status'        # restarted, uptime reset
```

**Pass:** app back within 5 s, `Uptime` on the page reset, no alarm fired
(a restart this fast should not page anyone).

## Exercise 2: bad revision (deploy gate + rollback)

**Hypothesis:** a revision that fails its health check never replaces the good one.

1. On a branch, break the health check deliberately, e.g. in `app/app.js`
   make `/api/health` return 500. Merge to `main`.
2. Watch the Deploy stage fail at `ValidateService` and auto-rollback kick in.
3. Confirm the page still serves the previous commit SHA.

**Pass:** deployment marked Failed, rollback deployment succeeded, SNS email
received, users never saw the bad revision. Revert the branch afterwards.

## Exercise 3: secret leak drill (defence in depth)

**Hypothesis:** a committed credential is stopped twice before production.

1. Add `AWS_SECRET_ACCESS_KEY=AKIA...` to a file and try to commit:
   pre-commit's gitleaks hook must block it.
2. Bypass locally with `git commit --no-verify` and push a branch + PR to main:
   the pipeline's Security stage must fail on the same finding.

**Pass:** both layers block. Delete the branch; the fake key was never real.

## Exercise 4: alert path (does the pager actually ring?)

**Hypothesis:** an alarm in ALARM state reaches a human.

```bash
aws cloudwatch set-alarm-state \
  --alarm-name cicd-demo-instance-status-failed \
  --state-value ALARM --state-reason "game day test"
```

**Pass:** SNS email arrives within a minute. The alarm returns to OK on the
next real evaluation period.

## Exercise 5: error-rate SLO signal

**Hypothesis:** a burst of 5xx responses shows up in CloudWatch within minutes.

Temporarily deploy a route that returns 500 (or use Exercise 2's branch) and
hit it 10 times. Check the `AwsCicdApp/ServerErrors` metric and the
`<stack>-app-5xx-errors` alarm.

**Pass:** metric filter counted the errors from the structured logs and the
alarm fired at the threshold. This proves the availability SLO in `slo.md`
is actually measured, not aspirational.
