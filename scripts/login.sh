#!/usr/bin/env bash
set -euo pipefail

# Web login to a sandbox. Registers the alias as the sandbox name itself.

# shellcheck disable=SC1091
source "$(dirname "$0")/org.sh"

NAME="${1:?usage: pnpm run login <sandbox-name>}"

# Validated because it becomes part of the URL hostname
if ! [[ "$NAME" =~ ^[A-Za-z0-9]{1,10}$ ]]; then
  echo "Sandbox name must be alphanumeric (max 10 chars): $NAME" >&2
  exit 1
fi

if pnpm exec sf org display --target-org "$NAME" >/dev/null 2>&1; then
  echo "Already authenticated: $NAME" >&2
  exit 0
fi

pnpm exec sf org login web --alias "$NAME" \
  --instance-url "https://${MY_DOMAIN}--${NAME}.sandbox.my.salesforce.com"
