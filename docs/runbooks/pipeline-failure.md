# Runbook: pipeline failure

**Alert:** SNS email from `<stack>-pipeline-alerts` (EventBridge rule on FAILED state), or a red stage in the CodePipeline console.
**Severity:** P2 — users are unaffected (the last good revision keeps running), but nothing new can ship.
**SLO impact:** deployment freshness and pipeline success rate.
**Escalation:** blocked > 1 hour with a critical fix waiting → consider a manual `aws deploy create-deployment` from the last green artifact.

## Step 1 — find the failed stage

CodePipeline console → pipeline → failed execution. The stage tells you where to look:

| Failed stage | Meaning | Go to |
|---|---|---|
| Source | CodeStar connection broken or branch missing | Step 2 |
| Security | gitleaks, npm audit, semgrep, or checkov found something | Step 3 |
| Build | dependency install, audit gate, or tests failed | Step 4 |
| Deploy | CodeDeploy lifecycle hook failed on the instance | `deployment-failure.md` |

## Step 2 — Source failures

- Developer Tools → Settings → Connections: status must be **Available**.
  If **Pending**, redo the GitHub app handshake.
- Confirm the branch in the pipeline's source action still exists.

## Step 3 — Security gate failures

Open the stage's CodeBuild logs. The `[n/4]` echo lines show which gate fired.

- **gitleaks (secret committed):** identify the finding in `gitleaks-report.json`
  (build artifacts). Rotate the secret immediately — a committed secret is a
  compromised secret, even if the push was blocked. Then purge it from history
  (`git filter-repo --path <file> --invert-paths`) and force-push the cleaned branch.
- **npm audit:** run `npm audit --omit=dev` locally in `app/`. Fix with
  `npm audit fix`, or bump the dependency; a Dependabot PR may already exist.
- **semgrep:** the log shows rule ID, file, and line. Fix the pattern; if it is
  a true false-positive, add an inline `# nosemgrep: <rule-id>` with a comment
  justifying it, and note it in the PR.
- **checkov:** fix the template finding. Only add a `--skip-check` entry if the
  risk is genuinely accepted, and document it in `buildspec-security.yml` and
  `threat-model.md`.

## Step 4 — Build failures

- `npm ci` fails: `package-lock.json` out of sync — run `npm install` locally and commit the lockfile.
- Tests fail: reproduce with `cd app && npm test`. The pipeline is doing its job — fix the test or the code, never bypass the stage.
- Audit gate fails here but not in Security: a new advisory published mid-pipeline; treat as Step 3 npm audit.

## Verify recovery

Push the fix (or **Release change** to re-run). Watch all four stages go green,
then confirm the app reports the new commit SHA at `http://<ec2-ip>:3000`.
