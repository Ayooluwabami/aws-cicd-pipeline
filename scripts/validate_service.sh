#!/bin/bash
# ValidateService hook — fail the deployment if the app isn't healthy.
set -u

RETRIES=12
SLEEP=5
URL="http://127.0.0.1:3000/api/health"

for i in $(seq 1 "$RETRIES"); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || true)
  if [ "$STATUS" = "200" ]; then
    echo "Health check passed (attempt $i)."
    exit 0
  fi
  echo "Health check attempt $i/$RETRIES returned '$STATUS' — retrying in ${SLEEP}s..."
  sleep "$SLEEP"
done

echo "Health check failed after $RETRIES attempts."
exit 1
