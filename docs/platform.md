# Platform engineering: the golden path

This repo doubles as a **service template**. The platform's job is to make the
safe way the easy way: a new service should inherit the security gates, the
deploy machinery, the monitoring, and the ops docs without anyone rebuilding
them by hand.

## What the paved road provides

| Concern | Provided by | Team writes |
|---|---|---|
| CI/CD with security gates | `buildspec.yml`, `buildspec-security.yml` | nothing |
| Local shift-left gates | `.pre-commit-config.yaml` | nothing |
| Deploy + rollback | `appspec.yml`, `scripts/` | nothing (keep `/api/health`) |
| Infrastructure | `infra/pipeline.yml` (one stack per service) | parameters only |
| Observability | structured logs → CloudWatch, `/metrics`, alarms | app-specific metrics |
| Operations | `docs/slo.md`, `docs/runbooks/`, postmortem template | service-specific SLO targets |
| Day-2 commands | `Makefile` (`make help`) | nothing |
| Catalog entry | `catalog-info.yaml` (Backstage-compatible) | owner + links |

## Scaffolding a new service

```bash
make scaffold NAME=orders-api DEST=../orders-api
# or directly:
platform/new-service.sh orders-api ../orders-api
```

The scaffolder copies the paved road, rewrites every `aws-cicd-app` reference
to the new service name (deploy directory, pm2 process, log config, stack
naming), initialises git, and writes a README with the next steps. The only
contract the app must keep is **`GET /api/health` returns 200 when healthy**,
because the deploy gate and the alarms are built on it.

## Day-2 operations

```bash
make pipeline-status   # stage-by-stage pipeline state
make logs              # tail structured app logs from CloudWatch
make audit             # same dependency gate the pipeline runs
make scan              # run all pre-commit gates
make infra-validate    # template check before pushing infra changes
```

## Platform decisions (and why)

- **One stack per service, not a shared pipeline.** Blast radius stays inside
  the service; teardown is one command; the template is the contract.
- **Gates live in the repo, not in the console.** A service cannot opt out of
  scanning by misclicking; changing a gate is a reviewed code change.
- **Monitoring is non-fatal at deploy time.** A broken CloudWatch agent must
  not block shipping a fix; degraded observability pages the on-call instead.
- **The health endpoint is the platform contract.** Everything else about the
  app is the team's business.
