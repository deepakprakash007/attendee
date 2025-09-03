# Attendee on GKE

This directory contains Kustomize/Helm agnostic Kubernetes manifests for deploying Attendee on GKE with autoscaling. It includes:
- Namespace and RBAC
- ConfigMap/Secrets from .env
- Web API Deployment + HPA
- Celery worker Deployment + HPA
- Redis not included (use managed Memorystore or hosted Redis). Database is Cloud SQL Postgres.
- Ingress via GKE Gateway API or Nginx. Here we provide GKE Ingress v1.
- Bot pod on-demand launcher via Kubernetes API (BotPodCreator) including optional Karpenter hints.

Use overlays/gke for GKE-specific resources like IngressClass and NEG annotations.
