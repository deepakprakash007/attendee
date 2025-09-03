# Deploy Attendee on Google Kubernetes Engine (GKE)

This guide covers production-ready deployment with scalability for both API and bot pods, using:
- GKE Autopilot or Standard + Cluster Autoscaler
- Optional Karpenter integration (see below)
- HPA for web and workers
- Cloud SQL for Postgres via Cloud SQL Auth Proxy sidecar
- Memorystore for Redis (or any hosted Redis), URL via REDIS_URL
- GKE Ingress + ManagedCertificate for TLS

See k8s/ for manifests. This README contains step-by-step instructions.
