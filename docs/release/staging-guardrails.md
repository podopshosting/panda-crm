# Staging Release Guardrails

This repo did not have a staging deploy path checked in. Use this playbook for narrow non-production validation slices only.

## Non-Negotiable Rules

1. Do not use production defaults for staging.
2. Deploy only one bounded slice at a time.
3. Capture a staging baseline and generate a rollback file before changing anything.
4. Keep database migrations manual and explicit.
5. Do not use this path for production.

## Required GitHub Configuration

Add these repository secrets:

- `STAGING_AWS_ACCESS_KEY_ID`
- `STAGING_AWS_SECRET_ACCESS_KEY`

Add these repository variables:

- `STAGING_AWS_REGION` (optional, defaults to `us-east-2`)
- `STAGING_ECS_CLUSTER`
- `STAGING_ECR_REGISTRY`
- `STAGING_FRONTEND_URL`
- `STAGING_FRONTEND_BUCKET`
- `STAGING_CLOUDFRONT_DISTRIBUTION_ID` (optional)
- `STAGING_API_BASE`
- `STAGING_GOOGLE_MAPS_SECRET_ID`

## Repo-Supported Staging Paths

Manual workflow:

- [deploy-staging-slice.yml](/Volumes/ExternalSSD/panda-crm-doc-upload-fix-20260326/.github/workflows/deploy-staging-slice.yml)

Local scripts used by that workflow:

- [services-slice.sh](/Volumes/ExternalSSD/panda-crm-doc-upload-fix-20260326/scripts/deploy/services-slice.sh)
- [frontend-env.sh](/Volumes/ExternalSSD/panda-crm-doc-upload-fix-20260326/scripts/deploy/frontend-env.sh)

Existing release helpers already support non-prod targets through environment overrides:

- [capture-prod-baseline.sh](/Volumes/ExternalSSD/panda-crm-doc-upload-fix-20260326/scripts/release/capture-prod-baseline.sh)
- [backup-frontend.sh](/Volumes/ExternalSSD/panda-crm-doc-upload-fix-20260326/scripts/release/backup-frontend.sh)
- [create-rollback-file.sh](/Volumes/ExternalSSD/panda-crm-doc-upload-fix-20260326/scripts/release/create-rollback-file.sh)

## Milestone Blocker Slice: Recommended Staging Scope

For the canonical milestone + PandaSign blocker retest, deploy only the touched slice:

- backend services:
  - `opportunities`
  - `documents`
- frontend:
  - enabled

Keep DB migration separate and manual:

- apply the additive milestone migration first
- do not run the backfill, only the dry-run

## Example Workflow Dispatch

- `deploy_frontend = true`
- `services = opportunities,documents`

After the workflow completes:

1. apply the staging DB migration if not already applied
2. run the blocker QA:
   - result wizard save/reload with Inspection Ran Date
   - disposition reload on opportunity detail
   - PandaSign public completion flow
   - authenticated agreement fetch
   - previously failing opportunity detail route
   - report preview/run checks

## Why This Exists

The production deploy paths in this repo are hard-wired to the production cluster, production frontend bucket, and production CloudFront distribution. This staging path is separate on purpose so the blocker retest can happen without any chance of touching production by accident.
