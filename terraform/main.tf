provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  service_name = "${var.service_name}-${var.environment}"
  image_tag    = var.image_tag != "" ? var.image_tag : var.environment
  image_name   = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repository_id}/${local.service_name}:${local.image_tag}"
}

resource "google_project_service" "required" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "service_images" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_registry_repository_id
  description   = "Docker images for FastAPI services"
  format        = "DOCKER"

  depends_on = [google_project_service.required]
}

resource "google_artifact_registry_repository_iam_member" "cloud_build_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.service_images.location
  repository = google_artifact_registry_repository.service_images.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

resource "null_resource" "image" {
  triggers = {
    dockerfile_hash   = filesha256("${path.module}/../Dockerfile")
    requirements_hash = filesha256("${path.module}/../requirements.txt")
    app_hash          = sha256(join("", [for file in fileset("${path.module}/../app", "**") : filesha256("${path.module}/../app/${file}")]))
    environment       = var.environment
    image_name        = local.image_name
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "gcloud builds submit --tag ${local.image_name} ."
  }

  depends_on = [google_artifact_registry_repository_iam_member.cloud_build_writer]
}

resource "google_cloud_run_v2_service" "api" {
  project  = var.project_id
  name     = local.service_name
  location = var.region

  template {
    scaling {
      min_instance_count = var.environment == "prod" ? 1 : 0
      max_instance_count = var.environment == "prod" ? 10 : 3
    }

    containers {
      image = local.image_name

      ports {
        container_port = 8080
      }

      env {
        name  = "APP_ENV"
        value = var.environment
      }
    }
  }

  depends_on = [
    google_project_service.required,
    null_resource.image,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
