#!/usr/bin/env bash
set -euo pipefail

# Deploy to a personal sandbox

# shellcheck disable=SC1091
source "$(dirname "$0")/org.sh"

NAME="${1:?usage: pnpm run deploy <sandbox-name>}"

# Deploying directly to the shared sandbox would diverge from the sandbox
# branch, so refuse it (hostnames are case-insensitive)
if [ "$(echo "$NAME" | tr '[:upper:]' '[:lower:]')" = "$SHARED_SANDBOX" ]; then
  echo "Deploy to the shared sandbox ($SHARED_SANDBOX) by pushing to the sandbox branch instead" >&2
  exit 1
fi

bash "$(dirname "$0")/login.sh" "$NAME"
pnpm exec sf project deploy start --target-org "$NAME"
