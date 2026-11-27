#!/usr/bin/env bash
set -euo pipefail

# デプロイ前の dry-run 検証

# shellcheck disable=SC1091
source "$(dirname "$0")/org.sh"

NAME="${1:-$SHARED_SANDBOX}"

bash "$(dirname "$0")/login.sh" "$NAME"
pnpm exec sf project deploy start --dry-run --target-org "$NAME"
