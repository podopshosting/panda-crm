#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT_DIR"

./scripts/deploy/preflight.sh

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "[frontend-env] ERROR: required env var $name is not set" >&2
    exit 1
  fi
}

AWS_REGION="${AWS_REGION:-us-east-2}"

require_env PANDA_DEPLOY_ENV_NAME
require_env PANDA_FRONTEND_BUCKET
require_env PANDA_API_BASE
require_env PANDA_GOOGLE_MAPS_API_KEY

BUILD_SHA=$(git rev-parse HEAD)
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

export VITE_API_BASE="$PANDA_API_BASE"
export VITE_GOOGLE_MAPS_API_KEY="$PANDA_GOOGLE_MAPS_API_KEY"
export VITE_BUILD_SHA="$BUILD_SHA"
export VITE_BUILD_TIME="$BUILD_TIME"

cd frontend
npm ci
npm run build

aws s3 sync dist "s3://${PANDA_FRONTEND_BUCKET}/" --delete --region "$AWS_REGION"

if [[ -n "${PANDA_CLOUDFRONT_DISTRIBUTION_ID:-}" ]]; then
  aws cloudfront create-invalidation \
    --distribution-id "$PANDA_CLOUDFRONT_DISTRIBUTION_ID" \
    --paths "/*" \
    --region "$AWS_REGION"
fi

echo "[frontend-env] Frontend deployed to ${PANDA_DEPLOY_ENV_NAME}"
