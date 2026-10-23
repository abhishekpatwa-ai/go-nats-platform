# go-nats-platform

A small event-driven platform to learn the Go + TypeScript + NATS stack on Kubernetes.
At Broadridge our services were Java (Spring Boot), so I built this to learn Go, TypeScript and NATS hands-on.

```text
Browser ─► ALB ─► web (TypeScript, nginx)
            └──► /api ─► api (Go) ──publish──► NATS JetStream (stream ORDERS)
                                                   │
                         PostgreSQL ◄──insert── worker (Go, durable consumer)
Prometheus + Grafana scrape api, worker, NATS and the cluster
```

| Folder | What |
|---|---|
| `apps/api` | Go HTTP API: `POST /api/orders` publishes to NATS, `GET /api/orders` reads PostgreSQL |
| `apps/worker` | Go worker: durable JetStream consumer, inserts into PostgreSQL, acks only after success |
| `apps/web` | TypeScript frontend compiled with `tsc`, served by unprivileged nginx |
| `helm/app` | Helm chart: Deployments, Services, Ingress (ALB), PostgreSQL StatefulSet, ServiceMonitor |
| `terraform` | VPC, EKS, add-ons, Load Balancer Controller, NATS, Prometheus/Grafana, ECR, GitHub OIDC role + RBAC |
| `.github/workflows` | Build (matrix) → Trivy scan → push to ECR → `helm upgrade` |

Cost: about $0.30–0.35 per hour. Destroy after every session.

## 1. Build the platform (~25–30 min)

```powershell
aws sso login --profile learn
$env:AWS_PROFILE = "learn"
cd terraform
terraform init
terraform apply
aws eks update-kubeconfig --name go-nats --region eu-west-1 --profile learn
kubectl get nodes
```

## 2. Deploy the app

GitHub → Actions → **build-and-deploy** → **Run workflow** (or push a change under `apps/` or `helm/`).

```powershell
kubectl get pods -n app
kubectl get ingress app -n app     # ADDRESS = the URL (open with http://)
```

## 3. Things to try

```powershell
# NATS: the stream and the worker's consumer
kubectl exec -n nats deploy/nats-box -- nats stream info ORDERS
kubectl exec -n nats deploy/nats-box -- nats consumer info ORDERS worker

# Drill: stop the worker, place orders, watch them wait in NATS, start it again
kubectl scale deploy/worker -n app --replicas=0
#   place 3 orders in the browser -> "Num Pending" grows in `consumer info`
kubectl scale deploy/worker -n app --replicas=1
#   pending drops to 0 and the orders appear — nothing was lost

# Grafana: http://localhost:3000, user admin
kubectl get secret -n monitoring monitoring-grafana -o jsonpath="{.data.admin-password}"   # base64; decode it
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

## 4. Destroy (order matters)

The ALB and the EBS disks were created by Kubernetes, not Terraform, so remove them first.

```powershell
kubectl delete ingress --all -n app
kubectl delete statefulset --all -n app
kubectl delete pvc --all -n app
cd terraform
terraform destroy -target="helm_release.nats"
kubectl delete pvc --all -n nats
terraform destroy
```
