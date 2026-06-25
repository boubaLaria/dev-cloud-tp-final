# GreenLogistics — TP Final Cloud-Native

> Sujet A — Tracking temps réel de livraison dernière mile  
> Stack LOCAL-FIRST · kind · Redpanda · ArgoCD · Linkerd · Prometheus

## Services

| Service | Port | Description |
|---------|------|-------------|
| `parcel-api` | 3000 | REST CRUD colis + PostgreSQL |
| `gps-ingestor` | 3001 | Ingestion positions GPS → Redpanda |
| `notifier` | 3003 | Worker Redpanda → alertes MailHog |
| `tracker-front` | 3002 | API publique de suivi |

## Démarrage rapide

```bash
# 1. Prérequis : Docker, kind, kubectl, helm, terraform, argocd CLI
# Voir SETUP.md pour les commandes d'installation complètes

# 2. Créer le cluster
kind create cluster --config kind-config.yaml

# 3. Provisionner la plateforme (ArgoCD, Redpanda, Vault, Prometheus, Loki...)
cd terraform && terraform init && terraform apply -auto-approve

# 4. Déployer l'application via ArgoCD
kubectl apply -f k8s/argocd-app.yaml

# 5. Accéder aux UIs
kubectl port-forward -n argocd svc/argocd-server 8080:443  # ArgoCD
kubectl port-forward -n monitoring svc/kps-grafana 9090:80  # Grafana
kubectl port-forward -n mail svc/mailhog 8025:8025           # MailHog
```

## Démo GPS

```bash
# Créer un colis en OUT_FOR_DELIVERY
PARCEL_ID=$(curl -s -X POST http://greenlogistics.local/api/parcels \
  -H "Content-Type: application/json" \
  -d '{"senderName":"Alice","recipientName":"Bob","recipientEmail":"bob@test.com",
       "recipientAddress":"12 rue de la Paix, Paris","recipientLat":48.8698,"recipientLng":2.3322}' \
  | jq -r '.id')

curl -X PATCH http://greenlogistics.local/api/parcels/$PARCEL_ID/status \
  -H "Content-Type: application/json" -d '{"status":"OUT_FOR_DELIVERY"}'

# Lancer la simulation GPS (approche progressive)
bash services/gps-ingestor/scripts/simulate.sh $PARCEL_ID

# Vérifier l'email dans MailHog : http://localhost:8025
```

## Structure

```
services/           # Code source des 4 microservices Node.js
k8s/                # Manifestes Kubernetes
terraform/          # IaC — cluster kind + plateforme
.github/workflows/  # CI/CD GitHub Actions
docs/               # Architecture, captures, slides
```

## Images GHCR

```
ghcr.io/OWNER/greenlogistics/parcel-api:latest
ghcr.io/OWNER/greenlogistics/gps-ingestor:latest
ghcr.io/OWNER/greenlogistics/notifier:latest
ghcr.io/OWNER/greenlogistics/tracker-front:latest
```

## Membres du groupe

- [Prénom Nom] — @github
- [Prénom Nom] — @github
