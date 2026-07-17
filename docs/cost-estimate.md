# Cost estimate

**Region assumed:** us-east-1 · **Last checked:** 2026-07-12 · Prices drift — treat as order-of-magnitude.

## Monthly running cost (demo topology)

| Resource | Sizing | Est. cost/month | Free tier |
|---|---|---|---|
| EC2 t3.micro | 1 instance, 730 h | ~$7.60 | 750 h/month for 12 months |
| EBS gp3 8 GB (encrypted) | root volume | ~$0.64 | 30 GB free for 12 months |
| CodePipeline | 1 active pipeline | $1.00 | first pipeline free |
| CodeBuild | 2 projects, general1.small, ~6 min/run, ~30 runs | ~$1.80 | 100 min/month free |
| CodeDeploy (EC2) | any volume | $0 | always free for EC2 |
| S3 artifacts | < 1 GB, short-lived | < $0.10 | 5 GB free for 12 months |
| SNS + EventBridge + 2 CloudWatch alarms | low volume | ~$0.20 | mostly within free tier |
| CodeStar connection | n/a | $0 | free |
| **Total** | | **~$11/month** (≈ $0 in year-one free tier) | |

## Cost controls in place

- `t3.micro` + gp3 keep compute and storage at the floor.
- Artifacts excluded `node_modules`, so S3 stays tiny; empty the bucket at teardown.
- Single stack teardown: `aws cloudformation delete-stack` removes everything billable.

## What would change in production

- ALB (+~$16/month) + ACM cert ($0) for HTTPS.
- 2+ instances in an ASG across AZs (linear instance cost).
- CloudWatch Synthetics canary for the availability SLO (~$0.0012/run).
