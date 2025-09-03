# Deploy Attendee on Google Kubernetes Engine (GKE)

This guide provides a production-ready deployment with scalability for both API and on-demand bot pods.

Key features
- GKE Autopilot or Standard + Cluster Autoscaler/Node Auto Provisioning
- Horizontal Pod Autoscalers for web and celery worker
- On-demand bot pods launched via Kubernetes API (BotPodCreator) with RBAC
- Cloud SQL for Postgres (Private IP recommended) and Memorystore for Redis
- S3-compatible storage for recordings (R2/S3/GCS S3-compatible endpoint)
- GKE Ingress + ManagedCertificate for TLS
- Workload Identity ready (annotate the KSA)

What you’ll deploy
- Namespace, ServiceAccount, RBAC
- ConfigMap and Secret (environment-driven config)
- Web Deployment + Service (gunicorn) and Worker Deployment (celery)
- HPAs and PodDisruptionBudgets
- Ingress with TLS via ManagedCertificate

Prerequisites
- gcloud, kubectl, and kustomize installed and authenticated
- A GCP project with billing enabled
- Cloud SQL (Postgres) with a Private IP in same VPC as the GKE cluster
- Memorystore (Redis) reachable from the cluster
- A domain you control for the app (e.g. app.example.com)

1) Build and push the Docker image
Use Artifact Registry or any registry you prefer.

Option A: Artifact Registry
- gcloud services enable artifactregistry.googleapis.com
- gcloud artifacts repositories create attendee --repository-format=docker --location=REGION
- docker build -t REGION-docker.pkg.dev/PROJECT/attendee/attendee:TAG .
- docker push REGION-docker.pkg.dev/PROJECT/attendee/attendee:TAG

Option B: GHCR or other registry
- docker build -t ghcr.io/YOUR_ORG/attendee:TAG .
- docker push ghcr.io/YOUR_ORG/attendee:TAG
- Create imagePullSecret 'regcred' in the attendee namespace

2) Prepare environment variables
- Copy deploy/gke/env.example to deploy/gke/.env and fill values.
- Use a Private IP for DATABASE_URL host so every pod (including on-demand bot pods) can connect:
  DATABASE_URL=postgresql://USER:PASSWORD@10.0.0.5:5432/attendee
- Set LAUNCH_BOT_METHOD=kubernetes and CUBER_RELEASE_VERSION to a unique value per release.
- If using a private registry, ensure BOT_POD_IMAGE matches your image repo.

3) Create the cluster and deploy
Run the helper script (edit vars to your values):

  deploy/gke/setup.sh <PROJECT_ID> <REGION> <CLUSTER_NAME> <DOMAIN> [--standard|--autopilot] IMAGE=<your/image:tag>

The script:
- Enables required APIs and creates the cluster (Autopilot or Standard)
- Applies Kustomize base and overlay
- Patches Ingress/ManagedCertificate with your DOMAIN
- Prints resources for verification

After setup:
- Create ConfigMap and Secret (see comments in setup.sh step 5) before applying overlays if you didn’t already.
- Optionally run the migration Job:
  kubectl -n attendee apply -f k8s/base/job-migrate.yaml
  kubectl -n attendee wait --for=condition=complete --timeout=10m job/attendee-migrate
  kubectl -n attendee delete job attendee-migrate

4) DNS and TLS
- Fetch the Ingress IP: kubectl -n attendee get ingress attendee-web
- Create a DNS A record for your domain to the Ingress IP.
- ManagedCertificate will provision TLS automatically.

5) Scaling and performance
- HPAs scale web and worker by CPU (tune thresholds in k8s/base/hpa.yaml)
- Ensure cluster-level autoscaling is enabled (Autopilot recommends itself; Standard can enable Node Auto Provisioning)
- For very high burst bot traffic, increase attendee-worker HPA maxReplicas and ensure sufficient node quotas.
- Bot pods use resource requests/limits from env (BOT_CPU_REQUEST, BOT_MEMORY_REQUEST, etc.). Tune as needed.

6) BotPodCreator and fast bot scale-out
- Code checks LAUNCH_BOT_METHOD=kubernetes and creates a Pod per bot.
- It requires CUBER_RELEASE_VERSION; BOT_POD_IMAGE defaults to nduncan{app}/{app} but you should set BOT_POD_IMAGE to your image repo.
- The bot pod inherits env from ConfigMap and Secret, so be sure DATABASE_URL/REDIS_URL are reachable from anywhere in the cluster (Private IPs recommended). No sidecar is present in bot pods.

7) Karpenter integration (optional)
- The code adds karpenter.sh/do-not-disrupt and karpenter.sh/do-not-evict annotations when USING_KARPENTER=true.
- NOTE: Karpenter is primarily used with EKS. GKE does not natively use Karpenter. These annotations are harmless on GKE.
- On GKE, prefer Cluster Autoscaler/Node Auto Provisioning for rapid node scale out.

8) Workload Identity and external services
- Annotate the attendee KSA with a GCP IAM service account if you need GCS/Secret Manager/etc:
  kubectl -n attendee annotate serviceaccount attendee iam.gke.io/gcp-service-account=YOUR_SA@PROJECT.iam.gserviceaccount.com --overwrite
- Redis Memorystore: set REDIS_URL (rediss:// for TLS) and DISABLE_REDIS_SSL if you must disable cert validation.
- Storage: configure S3-compatible credentials and endpoint (AWS, R2, or GCS S3 API compatible).

9) Operational notes
- Set SITE_DOMAIN and ensure CSRF_TRUSTED_ORIGINS in settings match your domain.
- Use kubectl rollout status deployment/attendee-web -n attendee to watch deploys.
- Use HPA and requests/limits to control P90 latency and burst absorption.
