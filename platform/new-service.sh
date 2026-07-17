#!/usr/bin/env bash
# Golden-path scaffolder: stamp out a new service that inherits this repo's
# pipeline gates, deploy hooks, monitoring, and ops docs.
#
#   platform/new-service.sh <service-name> <destination-dir>
#   e.g. platform/new-service.sh orders-api ../orders-api
set -euo pipefail

NAME="${1:-}"
DEST="${2:-}"

if [ -z "$NAME" ] || [ -z "$DEST" ]; then
  echo "Usage: platform/new-service.sh <service-name> <destination-dir>" >&2
  exit 1
fi
if ! echo "$NAME" | grep -Eq '^[a-z][a-z0-9-]{1,40}$'; then
  echo "Service name must be kebab-case (got: $NAME)" >&2
  exit 1
fi
if [ -e "$DEST" ]; then
  echo "Destination already exists: $DEST" >&2
  exit 1
fi

SRC="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$DEST"

# The paved road: everything a service needs to ship safely, nothing more.
cp -R "$SRC/app" "$DEST/app"
rm -rf "$DEST/app/node_modules" "$DEST/app/dist"
cp -R "$SRC/ansible" "$DEST/ansible" 2>/dev/null || true
rm -f "$DEST/ansible/inventory.ini"
cp -R "$SRC/puppet" "$DEST/puppet" 2>/dev/null || true
cp -R "$SRC/scripts" "$DEST/scripts"
cp -R "$SRC/monitoring" "$DEST/monitoring"
cp -R "$SRC/infra" "$DEST/infra"
mkdir -p "$DEST/docs"
cp -R "$SRC/docs/runbooks" "$DEST/docs/runbooks"
cp "$SRC/docs/slo.md" "$SRC/docs/incident-postmortem-template.md" "$DEST/docs/"
cp "$SRC/appspec.yml" "$SRC/buildspec.yml" "$SRC/buildspec-security.yml" \
   "$SRC/.pre-commit-config.yaml" "$SRC/.gitignore" "$SRC/Makefile" \
   "$SRC/catalog-info.yaml" "$DEST/"
mkdir -p "$DEST/.github"
cp "$SRC/.github/dependabot.yml" "$DEST/.github/dependabot.yml"
rm -rf "$DEST/app/node_modules"

# Rebrand every reference to the template service.
find "$DEST" -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.json' \
    -o -name '*.sh' -o -name '*.js' -o -name '*.html' -o -name 'Makefile' \) \
  -exec perl -pi -e "s/aws-cicd-app/${NAME}/g; s/aws-cicd-sample-app/${NAME}/g" {} +

cat > "$DEST/README.md" <<EOF
# ${NAME}

Scaffolded from the aws-cicd-pipeline golden path. Inherited out of the box:

- Gated pipeline: gitleaks, npm audit, semgrep, checkov before anything builds
- CodeDeploy rollout with health gate and auto-rollback (runs as ec2-user)
- Structured logs to CloudWatch, /metrics endpoint, error-rate alarm
- SLOs, runbooks, postmortem template in docs/
- \`make help\` for the paved-road commands

Next steps:
1. Replace the sample app in \`app/\` with the real service (keep /api/health).
2. \`git init && pre-commit install\`
3. Push to GitHub, then \`make infra-deploy STACK=${NAME}\` with your parameters.
EOF

git init -q "$DEST"
echo "Scaffolded ${NAME} at ${DEST}"
echo "Next: cd ${DEST} && pre-commit install && make test"
