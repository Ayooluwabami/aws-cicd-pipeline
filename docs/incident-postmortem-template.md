# Incident postmortem — <short title>

**Date of incident:**
**Duration:** <detection to resolution>
**Severity:** P1 (user-facing outage) / P2 (degraded or blocked deploys) / P3 (near miss)
**Author:**
**Status:** draft / reviewed / action items complete

> Blameless: name systems and gaps, not people. If a human error caused this,
> the real finding is the missing guardrail that allowed it.

## Summary (3 sentences max)

What broke, who noticed, how it was fixed.

## Impact

- User-visible impact and duration:
- Error budget consumed (see `slo.md`):
- Deployments blocked:

## Timeline (UTC)

| Time | Event |
|---|---|
|  | first bad change merged / infra event |
|  | alert fired (or a human noticed — note if no alert existed) |
|  | investigation started |
|  | mitigation applied |
|  | verified healthy |

## Root cause

Not "the deploy failed" — why did it fail, and why did the pipeline's gates
not catch it before production?

## What went well / what went poorly

-

## Action items

| Action | Type (prevent / detect / mitigate) | Owner | Due |
|---|---|---|---|
|  |  |  |  |

Every P1/P2 must produce at least one **prevent** or **detect** item — a new
test, a new gate, a new alarm — not just "be more careful."
