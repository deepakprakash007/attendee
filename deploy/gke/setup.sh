#!/usr/bin/env bash
set -euo pipefail

# This script sets up GKE resources and deploys manifests.
# Requirements: gcloud, kubectl, kustomize (or kubectl kustomize), and configured gcloud auth.

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <GCP_PROJECT_ID> <REGION> <CLUSTER_NAME> <DOMAIN> [--standard|--autopilot] [IMAGE=<registry/image:tag>]"
  exit 1
fi

PROJECT_ID=$1
REGION=$2
CLUSTER_NAME=$3
DOMAIN=$4
MODE=${5:---standard}
IMAGE=${IMAGE:-}

# 1. APIs

gcloud services enable container.googleapis.com cloudresourcemanager.googleapis.com sqladmin.googleapis.com compute.googleapis.com servicenetworking.googleapis.com certificatemanager.googleapis.com --project ${PROJECT_ID}

# 2. Create cluster
if [[ "$MODE" == "--autopilot" ]]; then
  gcloud container clusters create-auto ${CLUSTER_NAME} --region=${REGION} --project=${PROJECT_ID}
else
  gcloud container clusters create ${CLUSTER_NAME} --region=${REGION} --project=${PROJECT_ID} \
    --machine-type=e2-standard-4 --num-nodes=3 --enable-ip-alias --release-channel=regular \
    --addons=HttpLoadBalancing,HorizontalPodAutoscaling,NodeLocalDNS --metadata disable-legacy-endpoints=true
  # Enable cluster autoscaling and node auto-provisioning as needed (optional):
  # gcloud container clusters update ${CLUSTER_NAME} --region ${REGION} --enable-autoscaling --min-nodes 1 --max-nodes 100 --project ${PROJECT_ID}
fi

gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION} --project ${PROJECT_ID}

# 3. Namespace first
kubectl apply -f k8s/base/namespace.yaml

# 3b. Apply base manifests (ConfigMap/Secret will be picked up if present)
kubectl apply -k k8s/base

# 4. Create image pull secret (if using private registry)
# kubectl -n attendee create secret docker-registry regcred --docker-server=... --docker-username=... --docker-password=... --docker-email=...

# 5. Create ConfigMap from env.example (edit first!) and Secret from sensitive vars
# Edit deploy/gke/env.example and save to deploy/gke/.env, prefer DATABASE_URL with a Private IP host so bot pods can connect without a sidecar.
# If deploy/gke/.env exists, auto-create/update the ConfigMap now:
if [[ -f deploy/gke/.env ]]; then
  kubectl -n attendee create configmap env --from-env-file=deploy/gke/.env --dry-run=client -o yaml | kubectl apply -f -
else
  echo "deploy/gke/.env not found. Create it from deploy/gke/env.example and re-run to auto-create the ConfigMap."
fi
# Create secrets interactively or via CI (example):
# kubectl -n attendee create secret generic app-secrets \
#   --from-literal=DJANGO_SECRET_KEY=... \
#   --from-literal=CREDENTIALS_ENCRYPTION_KEY=... \
#   --from-literal=STRIPE_SECRET_KEY=... \
#   --from-literal=STRIPE_WEBHOOK_SECRET=... \
#   --from-literal=EMAIL_HOST_USER=... \
#   --from-literal=EMAIL_HOST_PASSWORD=... \
#   --from-literal=ZOOM_MEETING_SDK_KEY=... \
#   --from-literal=ZOOM_MEETING_SDK_SECRET=... \
#   --dry-run=client -o yaml | kubectl apply -f -

# 6. Optionally set image for deployments using kustomize (IMAGE=registry/image:tag)
if [[ -n "${IMAGE}" ]]; then
  pushd k8s/overlays/gke >/dev/null
  kustomize edit set image ghcr.io/deepakprakash007/attendee:latest=${IMAGE}
  popd >/dev/null
fi

# 7. Deploy application (after ConfigMap/Secret)
kubectl apply -k k8s/overlays/gke

# 8. Patch Ingress host and ManagedCertificate domain to provided DOMAIN
kubectl -n attendee patch ingress attendee-web --type=json -p='[{"op":"replace","path":"/spec/rules/0/host","value":"'"${DOMAIN}"'"}]'
kubectl -n attendee patch managedcertificate attendee-cert --type merge -p "{\"spec\":{\"domains\":[\"${DOMAIN}\"]}}" || true

# 9. (One-time) Run migrations and collectstatic via Job
# kubectl -n attendee apply -f k8s/base/job-migrate.yaml
# kubectl -n attendee wait --for=condition=complete --timeout=10m job/attendee-migrate || kubectl -n attendee logs job/attendee-migrate
# kubectl -n attendee delete job attendee-migrate || true

# 10. Verify
kubectl -n attendee get pods,svc,ingress,hpa

echo "Deployment initiated. Create a DNS A record for ${DOMAIN} pointing to the Ingress IP once provisioned."
