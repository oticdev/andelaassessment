#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-andela-assessment-494309}"
REGION="${REGION:-us-central1}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-oticdev/andelaassessment}"
STATE_BUCKET="${TERRAFORM_STATE_BUCKET:-${PROJECT_ID}-terraform-state}"
ARTIFACT_REPOSITORY="${ARTIFACT_REPOSITORY:-fastapi-services}"
SERVICE_ACCOUNT_ID="${SERVICE_ACCOUNT_ID:-github-actions-deployer}"
POOL_ID="${POOL_ID:-github-actions}"
PROVIDER_ID="${PROVIDER_ID:-github-oticdev-andelaassessment}"

usage() {
  cat <<EOF
Usage: $0 [options]

Bootstraps Google Cloud for GitHub Actions deployments using Workload Identity Federation.

Options:
  --project-id ID             Google Cloud project ID. Default: ${PROJECT_ID}
  --region REGION             Google Cloud region. Default: ${REGION}
  --github-repository REPO    GitHub repository in owner/name form. Default: ${GITHUB_REPOSITORY}
  --state-bucket BUCKET       Terraform state bucket. Default: ${STATE_BUCKET}
  --artifact-repository ID    Artifact Registry repository ID. Default: ${ARTIFACT_REPOSITORY}
  --service-account-id ID     Deployment service account ID. Default: ${SERVICE_ACCOUNT_ID}
  --pool-id ID                Workload Identity Pool ID. Default: ${POOL_ID}
  --provider-id ID            Workload Identity Provider ID. Default: ${PROVIDER_ID}
  -h, --help                  Show this help text.

Outputs the GitHub secret values needed by the deployment workflows.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --github-repository)
      GITHUB_REPOSITORY="$2"
      shift 2
      ;;
    --state-bucket)
      STATE_BUCKET="$2"
      shift 2
      ;;
    --artifact-repository)
      ARTIFACT_REPOSITORY="$2"
      shift 2
      ;;
    --service-account-id)
      SERVICE_ACCOUNT_ID="$2"
      shift 2
      ;;
    --pool-id)
      POOL_ID="$2"
      shift 2
      ;;
    --provider-id)
      PROVIDER_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")"
PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

gcloud services enable \
  artifactregistry.googleapis.com \
  iamcredentials.googleapis.com \
  run.googleapis.com \
  serviceusage.googleapis.com \
  sts.googleapis.com \
  --project="${PROJECT_ID}"

gcloud storage buckets describe "gs://${STATE_BUCKET}" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access

gcloud artifacts repositories describe "${ARTIFACT_REPOSITORY}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" >/dev/null 2>&1 || \
  gcloud artifacts repositories create "${ARTIFACT_REPOSITORY}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --repository-format=docker \
    --description="Docker images for andelaassessment"

gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "${SERVICE_ACCOUNT_ID}" \
    --project="${PROJECT_ID}" \
    --display-name="GitHub Actions Deployer"

for role in \
  roles/artifactregistry.writer \
  roles/iam.serviceAccountUser \
  roles/run.admin \
  roles/serviceusage.serviceUsageAdmin
do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="${role}" \
    --quiet
done

gcloud storage buckets add-iam-policy-binding "gs://${STATE_BUCKET}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/storage.admin" \
  --quiet

gcloud iam workload-identity-pools describe "${POOL_ID}" \
  --project="${PROJECT_ID}" \
  --location=global >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools create "${POOL_ID}" \
    --project="${PROJECT_ID}" \
    --location=global \
    --display-name="GitHub Actions"

gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
  --project="${PROJECT_ID}" \
  --location=global \
  --workload-identity-pool="${POOL_ID}" >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
    --project="${PROJECT_ID}" \
    --location=global \
    --workload-identity-pool="${POOL_ID}" \
    --display-name="GitHub ${GITHUB_REPOSITORY}" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository == '${GITHUB_REPOSITORY}'"

gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPOSITORY}" \
  --quiet

cat <<EOF

Bootstrap complete.

Set these GitHub repository secrets:

GCP_PROJECT_ID=${PROJECT_ID}
TERRAFORM_STATE_BUCKET=${STATE_BUCKET}
GCP_SERVICE_ACCOUNT=${SERVICE_ACCOUNT_EMAIL}
GCP_WORKLOAD_IDENTITY_PROVIDER=${PROVIDER_RESOURCE}
EOF
