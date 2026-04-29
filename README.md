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
- `GCP_SA_KEY`: JSON key for a deployment service account
- `TERRAFORM_STATE_BUCKET`: globally unique GCS bucket name for Terraform state

You can create the deployer service account and local key with:

```bash
scripts/create-gcp-deployer.sh andela-assessment-494309
```

Use the contents of `github-actions-deployer-key.json` as `GCP_SA_KEY`.

## Manual Terraform Deploy

Prerequisites:

- Google Cloud project with billing enabled
- `gcloud` CLI authenticated with permissions to enable services, create Artifact Registry repos, submit Cloud Build jobs, and deploy Cloud Run
- Terraform installed

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
  -var="environment=dev"
```

Terraform outputs the Cloud Run service URL when deployment completes.

To allow public access, keep `allow_unauthenticated = true`. Set it to `false` if you want IAM-protected access.
