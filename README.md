# andelaassessment

Minimal FastAPI service prepared for branch-based deployments to Google Cloud Run with Terraform and GitHub Actions.

## Run Locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000` or `http://127.0.0.1:8000/docs`.

## Environments

| Branch | Environment | Deployment |
| --- | --- | --- |
| `dev` | `dev` | Automatic on push |
| `staging` | `staging` | Automatic on push or merge |
| `main` | `prod` | Manual GitHub Actions workflow dispatch |

Each environment deploys its own Cloud Run service:

- `andelaassessment-dev`
- `andelaassessment-staging`
- `andelaassessment-prod`

Terraform state is stored in a GCS bucket with separate prefixes for each environment.

## GitHub Secrets

Set these repository secrets before relying on GitHub Actions deployments:

- `GCP_PROJECT_ID`: Google Cloud project ID, for example `andela-assessment-494309`
- `TERRAFORM_STATE_BUCKET`: globally unique GCS bucket name for Terraform state
- `GCP_SERVICE_ACCOUNT`: deployment service account email
- `GCP_WORKLOAD_IDENTITY_PROVIDER`: Workload Identity Federation provider resource name

Bootstrap Google Cloud, Artifact Registry, Terraform state, and keyless GitHub authentication with:

```bash
scripts/bootstrap-gcp.sh
```

The script prints the exact GitHub secret values to set. It uses Workload Identity Federation, so there is no service account JSON key to create, store, rotate, or leak.

## Destroy Resources

Destroy all Terraform-managed environments:

```bash
scripts/destroy-gcp.sh
```

Destroy Terraform-managed resources and delete the Terraform state bucket:

```bash
scripts/destroy-gcp.sh --delete-state-bucket
```

Destroy Terraform-managed resources and delete the Artifact Registry repository:

```bash
scripts/destroy-gcp.sh --delete-artifact-repo
```

Destroy everything and delete the entire Google Cloud project:

```bash
scripts/destroy-gcp.sh --delete-project
```

The script requires typing the project ID before it proceeds.

## Manual Terraform Deploy

Prerequisites:

- Google Cloud project with billing enabled
- `gcloud` CLI authenticated with permissions to deploy Cloud Run
- Terraform installed
- A pushed container image in Artifact Registry

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project andela-assessment-494309

cd terraform
terraform init \
  -backend-config="bucket=YOUR_TERRAFORM_STATE_BUCKET" \
  -backend-config="prefix=terraform/state/dev"
terraform apply \
  -var="project_id=andela-assessment-494309" \
  -var="environment=dev" \
  -var="image_name=us-central1-docker.pkg.dev/andela-assessment-494309/fastapi-services/andelaassessment-dev:TAG"
```

Terraform outputs the Cloud Run service URL when deployment completes.

To allow public access, keep `allow_unauthenticated = true`. Set it to `false` if you want IAM-protected access.
