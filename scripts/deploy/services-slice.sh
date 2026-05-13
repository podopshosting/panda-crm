#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT_DIR"

./scripts/deploy/preflight.sh

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[services-slice] ERROR: missing required command: $1" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "[services-slice] ERROR: required env var $name is not set" >&2
    exit 1
  fi
}

for cmd in aws docker git; do
  require_cmd "$cmd"
done

AWS_REGION="${AWS_REGION:-us-east-2}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short=12 HEAD)}"
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

require_env PANDA_DEPLOY_ENV_NAME
require_env PANDA_ECS_CLUSTER
require_env PANDA_ECR_REGISTRY
require_env PANDA_DEPLOY_SERVICES

export AWS_PAGER=""

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$PANDA_ECR_REGISTRY"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

resolve_repo() {
  local service_name="$1"
  if aws ecr describe-repositories --repository-names "panda-crm/${service_name}" --region "$AWS_REGION" >/dev/null 2>&1; then
    printf 'panda-crm/%s' "$service_name"
    return 0
  fi
  if aws ecr describe-repositories --repository-names "panda-crm-${service_name}" --region "$AWS_REGION" >/dev/null 2>&1; then
    printf 'panda-crm-%s' "$service_name"
    return 0
  fi
  return 1
}

resolve_ecs_service() {
  local service_name="$1"
  local candidate=""
  for candidate in "${service_name}-service" "panda-crm-${service_name}" "${service_name}"; do
    if aws ecs describe-services \
      --cluster "$PANDA_ECS_CLUSTER" \
      --services "$candidate" \
      --region "$AWS_REGION" \
      --query 'services[0].status' \
      --output text 2>/dev/null | grep -qE 'ACTIVE|DRAINING'; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

IFS=',' read -r -a raw_services <<< "$PANDA_DEPLOY_SERVICES"

for raw_service in "${raw_services[@]}"; do
  service_name="$(trim "$raw_service")"
  [[ -z "$service_name" ]] && continue

  if [[ ! -f "services/${service_name}/Dockerfile" ]]; then
    echo "[services-slice] ERROR: services/${service_name}/Dockerfile not found" >&2
    exit 1
  fi

  image_repo="$(resolve_repo "$service_name")" || {
    echo "[services-slice] ERROR: no ECR repo found for $service_name" >&2
    exit 1
  }

  ecs_service="$(resolve_ecs_service "$service_name")" || {
    echo "[services-slice] ERROR: no ECS service found for $service_name in cluster $PANDA_ECS_CLUSTER" >&2
    exit 1
  }

  image_uri="${PANDA_ECR_REGISTRY}/${image_repo}"

  echo "[services-slice] Building ${service_name} for ${PANDA_DEPLOY_ENV_NAME}"
  docker build \
    --build-arg BUILD_SHA="$IMAGE_TAG" \
    --build-arg BUILD_TIME="$BUILD_TIME" \
    -t "${image_uri}:${IMAGE_TAG}" \
    -t "${image_uri}:latest" \
    -f "services/${service_name}/Dockerfile" \
    .

  echo "[services-slice] Pushing ${service_name}"
  docker push "${image_uri}:${IMAGE_TAG}"
  docker push "${image_uri}:latest"

  echo "[services-slice] Updating ECS service ${ecs_service}"
  aws ecs update-service \
    --cluster "$PANDA_ECS_CLUSTER" \
    --service "$ecs_service" \
    --force-new-deployment \
    --region "$AWS_REGION" >/dev/null
done

echo "[services-slice] Services deployed to ${PANDA_DEPLOY_ENV_NAME}"
