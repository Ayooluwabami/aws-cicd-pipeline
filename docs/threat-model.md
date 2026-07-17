# Threat Model — AWS DevSecOps Pipeline (CodePipeline / CodeBuild / CodeDeploy / EC2)

**System:** aws-cicd-pipeline
**Last reviewed:** 2026-07-12
**Review trigger:** initial architecture. Re-review on any architectural change, new data flow, or security incident.

> **Scope:** the CodePipeline pipeline, CodeBuild projects, CodeDeploy application,
> the EC2 deployment target, the S3 artifact bucket, and the GitHub repository.
> Out of scope: end-user devices and the AWS control plane itself.

## 1. Assets (what an attacker wants)

| Asset | Sensitivity | Impact if compromised |
|---|---|---|
| AWS account credentials | Critical | Full account takeover; unlimited spend |
| CodePipeline/CodeBuild service roles | High | Run arbitrary builds with pipeline permissions |
| GitHub repository (`main`) | Critical | Inject code that the pipeline deploys automatically |
| CodeStar connection | High | Read source; trigger poisoned pipeline runs |
| S3 artifact bucket | High | Replace the deployment bundle between Build and Deploy |
| EC2 instance role | Medium | Read artifacts; pivot via instance metadata |
| The running app / port 3000 | Low | DoS, reconnaissance |
| Build logs | Medium | Reveal environment structure and error details |

## 2. Trust boundaries

1. **Internet → GitHub**: anyone can open PRs; only `main` deploys.
   *Mitigation:* branch protection + pre-commit hooks; pipeline triggers only on `main`.
2. **GitHub → CodePipeline**: the CodeStar connection is the ingestion point for all code.
   *Mitigation:* connection scoped to one repository; Security stage gates every revision.
3. **Pipeline → S3 artifact bucket**: artifacts cross stages through S3.
   *Mitigation:* SSE-S3, TLS-only bucket policy, public access blocked, roles scoped to this bucket only.
4. **CodeDeploy → EC2**: the agent executes lifecycle scripts as root.
   *Mitigation:* scripts come only from the gated artifact; app itself drops to `ec2-user`.
5. **Internet → EC2 port 3000**: the only public application surface.
   *Mitigation:* security group exposes 22 (restricted CIDR) and 3000 only; helmet + rate limiting on the app; IMDSv2 blocks SSRF metadata theft.

## 3. Key threats and mitigations (STRIDE)

| Threat | Category | Mitigation in this repo |
|---|---|---|
| Committed AWS keys deploy to prod | Information disclosure | gitleaks in pre-commit **and** blocking Security stage |
| Malicious/vulnerable dependency | Tampering | `npm audit` gate (Security + Build), Dependabot PRs |
| Injection or unsafe code pattern | Tampering | Semgrep SAST gate |
| Misconfigured infra (open SG, unencrypted volume) | Elevation of privilege | checkov gate on `infra/`; IMDSv2; encrypted EBS |
| Artifact swapped in S3 | Tampering | TLS-only policy, scoped IAM writes, bucket not public |
| Compromised instance reads other buckets | Elevation of privilege | instance role limited to artifact bucket read + SSM |
| Broken deploy stays live | Availability | ValidateService health gate + automatic rollback |
| Silent pipeline failure | Repudiation | EventBridge → SNS alert; CloudWatch alarms on the instance |
| Metadata credential theft via SSRF | Information disclosure | IMDSv2 required (session tokens, hop limit 1) |

## 4. Accepted risks

- App served over plain HTTP on port 3000 (demo). Production would front it
  with an ALB + ACM certificate and restrict the instance SG to the ALB.
- Single instance, single AZ (demo cost). Production would use an ASG across AZs.
- `GET /metrics` (Prometheus) is publicly reachable on port 3000 and reveals
  process-level details. Acceptable for a demo; production would restrict it
  to an internal scrape source (SG rule or auth middleware).
- Checkov skips documented in `buildspec-security.yml`.
