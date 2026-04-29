#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${1:-andela-assessment-494309}"
SERVICE_ACCOUNT_ID="${2:-github-actions-deployer}"
KEY_FILE="${3:-github-actions-deployer-key.json}"

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "${SERVICE_ACCOUNT_ID}" \
    --project="${PROJECT_ID}" \
    --display-name="GitHub Actions Deployer"

for role in \
  roles/artifactregistry.admin \
  roles/cloudbuild.builds.editor \
  roles/iam.serviceAccountUser \
  roles/run.admin \
  roles/serviceusage.serviceUsageAdmin \
  roles/storage.admin
do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="${role}" \
    --quiet
done

gcloud iam service-accounts keys create "${KEY_FILE}" \
  --iam-account="${SERVICE_ACCOUNT_EMAIL}" \
  --project="${PROJECT_ID}"

printf 'Created deployer key: %s\n' "${KEY_FILE}"
