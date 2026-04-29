#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-andela-assessment-494309}"
REGION="${REGION:-us-central1}"
STATE_BUCKET="${TERRAFORM_STATE_BUCKET:-${PROJECT_ID}-terraform-state}"
SERVICE_ACCOUNT_ID="${SERVICE_ACCOUNT_ID:-github-actions-deployer}"
ARTIFACT_REPOSITORY="${ARTIFACT_REPOSITORY:-fastapi-services}"
DELETE_PROJECT=false
DELETE_STATE_BUCKET=false
DELETE_SERVICE_ACCOUNT=false
DELETE_ARTIFACT_REPOSITORY=false

usage() {
  cat <<EOF
Usage: $0 [options]

Destroys the dev, staging, and prod Terraform deployments for this project.

Options:
  --project-id ID             Google Cloud project ID. Default: ${PROJECT_ID}
  --region REGION             Google Cloud region. Default: ${REGION}
  --state-bucket BUCKET       Terraform state bucket. Default: ${STATE_BUCKET}
  --delete-state-bucket       Delete the Terraform state bucket after destroying resources.
  --delete-artifact-repo      Delete the Artifact Registry Docker repository.
  --delete-service-account    Delete the GitHub Actions deployer service account.
  --delete-project            Delete the entire Google Cloud project after Terraform destroy.
  -h, --help                  Show this help text.

Environment variables:
  PROJECT_ID
  REGION
  TERRAFORM_STATE_BUCKET
  SERVICE_ACCOUNT_ID
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
    --state-bucket)
      STATE_BUCKET="$2"
      shift 2
      ;;
    --delete-state-bucket)
      DELETE_STATE_BUCKET=true
      shift
      ;;
    --delete-artifact-repo)
      DELETE_ARTIFACT_REPOSITORY=true
      shift
      ;;
    --delete-service-account)
      DELETE_SERVICE_ACCOUNT=true
      shift
      ;;
    --delete-project)
      DELETE_PROJECT=true
      DELETE_STATE_BUCKET=true
      DELETE_ARTIFACT_REPOSITORY=true
      shift
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

confirm() {
  local prompt="$1"
  read -r -p "${prompt} Type '${PROJECT_ID}' to continue: " response
  [[ "${response}" == "${PROJECT_ID}" ]]
}

if ! confirm "This will destroy Terraform-managed Cloud Run and Artifact Registry resources in ${PROJECT_ID}."; then
  echo "Aborted."
  exit 1
fi

for environment in dev staging prod; do
  echo "Destroying ${environment}..."
  (
    cd terraform
    terraform init \
      -backend-config="bucket=${STATE_BUCKET}" \
      -backend-config="prefix=terraform/state/${environment}" \
      -reconfigure

    terraform destroy \
      -auto-approve \
      -var="project_id=${PROJECT_ID}" \
      -var="region=${REGION}" \
      -var="environment=${environment}" \
      -var="image_name=${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPOSITORY}/andelaassessment-${environment}:destroy"
  )
done

if [[ "${DELETE_SERVICE_ACCOUNT}" == "true" ]]; then
  SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
  echo "Deleting service account ${SERVICE_ACCOUNT_EMAIL}..."
  gcloud iam service-accounts delete "${SERVICE_ACCOUNT_EMAIL}" \
    --project="${PROJECT_ID}" \
    --quiet || true
fi

if [[ "${DELETE_ARTIFACT_REPOSITORY}" == "true" ]]; then
  echo "Deleting Artifact Registry repository ${ARTIFACT_REPOSITORY}..."
  gcloud artifacts repositories delete "${ARTIFACT_REPOSITORY}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --quiet || true
fi

if [[ "${DELETE_STATE_BUCKET}" == "true" ]]; then
  echo "Deleting Terraform state bucket gs://${STATE_BUCKET}..."
  gcloud storage rm --recursive "gs://${STATE_BUCKET}" --quiet || true
fi

if [[ "${DELETE_PROJECT}" == "true" ]]; then
  if ! confirm "This will delete the entire Google Cloud project ${PROJECT_ID}."; then
    echo "Skipped project deletion."
    exit 0
  fi

  gcloud projects delete "${PROJECT_ID}" --quiet
fi

echo "Destroy complete."
