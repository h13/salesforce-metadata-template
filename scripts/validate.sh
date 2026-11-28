#!/usr/bin/env bash
set -euo pipefail

# Dry-run validation before pushing

# shellcheck disable=SC1091
source "$(dirname "$0")/org.sh"

NAME="${1:-$SHARED_SANDBOX}"

bash "$(dirname "$0")/login.sh" "$NAME"
pnpm exec sf project deploy start --dry-run --target-org "$NAME"
