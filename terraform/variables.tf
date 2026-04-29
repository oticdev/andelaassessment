variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
}

variable "region" {
  description = "Google Cloud region for Artifact Registry and Cloud Run."
  type        = string
  default     = "us-central1"
}

variable "service_name" {
  description = "Base Cloud Run service name."
  type        = string
  default     = "andelaassessment"
}

variable "environment" {
  description = "Deployment environment. Expected values are dev, staging, or prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, or prod."
  }
}

variable "artifact_registry_repository_id" {
  description = "Artifact Registry Docker repository ID."
  type        = string
  default     = "fastapi-services"
}

variable "allow_unauthenticated" {
  description = "Whether to make the Cloud Run service publicly invokable."
  type        = bool
  default     = true
}

variable "image_tag" {
  description = "Container image tag to deploy. Defaults to the selected environment."
  type        = string
  default     = ""
}
