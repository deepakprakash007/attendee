#!/usr/bin/env bash
set -euo pipefail

# This script sets up GKE resources and deploys manifests.
# Requirements: gcloud, kubectl, kustomize (or kubectl kustomize), and configured gcloud auth.

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <GCP_PROJECT_ID> <REGION> <CLUSTER_NAME> <DOMAIN> [--standard|--autopilot]"
  exit 1
fi

PROJECT_ID=$1
REGION=$2
CLUSTER_NAME=$3
DOMAIN=$4
MODE=${5:---standard}

# 1. APIs

gcloud services enable container.googleapis.com cloudresourcemanager.googleapis.com sqladmin.googleapis.com compute.googleapis.com servicenetworking.googleapis.com certificatemanager.googleapis.com --project ${PROJECT_ID}

# 2. Create cluster
if [[ "$MODE" == "--autopilot" ]]; then
  gcloud container clusters create-auto ${CLUSTER_NAME} --region=${REGION} --project=${PROJECT_ID}
else
  gcloud container clusters create ${CLUSTER_NAME} --region=${REGION} --project=${PROJECT_ID} \
    --machine-type=e2-standard-4 --num-nodes=3 --enable-ip-alias --release-channel=regular \
    --addons=HttpLoadBalancing,HorizontalPodAutoscaling,NodeLocalDNS --metadata disable-legacy-endpoints=true
fi

gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION} --project ${PROJECT_ID}

# 3. Namespace and base manifests
kubectl apply -k k8s/base

# 4. Managed Certificate and Ingress domain update
# Patch managed certificate domain if different
kubectl -n attendee patch managedcertificate attendee-cert --type merge -p "{\"spec\":{\"domains\":[\"${DOMAIN}\"]}}" || true

# 5. Create image pull secret (if using private registry)
# kubectl -n attendee create secret docker-registry regcred --docker-server=... --docker-username=... --docker-password=... --docker-email=...

# 6. Create ConfigMap from env.example (edit first!) and Secret from sensitive vars
# Edit deploy/gke/env.example and save to deploy/gke/.env
# Then run:
#    kubectl -n attendee create configmap env --from-env-file=deploy/gke/.env --dry-run=client -o yaml | kubectl apply -f -
#    kubectl -n attendee create secret generic app-secrets \
#       --from-literal=DJANGO_SECRET_KEY=... \
#       --from-literal=CREDENTIALS_ENCRYPTION_KEY=... \
#       --from-literal=STRIPE_SECRET_KEY=... \
#       --from-literal=STRIPE_WEBHOOK_SECRET=... \
#       --from-literal=EMAIL_HOST_USER=... \
#       --from-literal=EMAIL_HOST_PASSWORD=... \
#       --from-literal=ZOOM_MEETING_SDK_KEY=... \
#       --from-literal=ZOOM_MEETING_SDK_SECRET=... \
#       --dry-run=client -o yaml | kubectl apply -f -

# 7. Deploy application (after ConfigMap/Secret)
kubectl apply -k k8s/overlays/gke

# 8. Verify
kubectl -n attendee get pods,svc,ingress,hpa

echo "Deployment initiated. Configure DNS A record for ${DOMAIN} to point to the Ingress IP once provisioned."
