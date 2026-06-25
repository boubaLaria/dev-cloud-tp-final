# SETUP — Reproduire le cluster en < 30 min

## Prérequis

```bash
# macOS
brew install kind kubectl helm terraform argocd trivy k9s
brew install --cask docker

# Vérification
docker version && kubectl version --client && kind version && \
  helm version && terraform version && argocd version --client && trivy version
```

## 1. Créer le cluster kind

```bash
kind create cluster --config kind-config.yaml --image kindest/node:v1.30.0
kubectl cluster-info --context kind-greenlogistics
kubectl get nodes  # doit afficher 3 nodes Ready
```

## 1b. Installer ingress-nginx + configurer /etc/hosts

```bash
# Ingress controller pour kind (expose port 80 mappé sur le host)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

# Ajouter l'entrée locale pour le domaine de démo
echo "127.0.0.1 greenlogistics.local" | sudo tee -a /etc/hosts
```

## 2. Provisionner la plateforme avec Terraform

```bash
cd terraform
terraform init
terraform apply -auto-approve
# Durée : ~8-10 min (Redpanda + kube-prometheus-stack sont les plus lents)
```

## 3. Initialiser Vault

```bash
# Mettre la DATABASE_URL dans Vault
kubectl -n vault exec -it vault-0 -- vault kv put \
  secret/greenlogistics/api \
  database_url="postgresql://gluser:changeme-use-vault-in-prod@postgres.app.svc.cluster.local:5432/greenlogistics"

# Créer le token External Secrets
kubectl -n external-secrets create secret generic vault-token \
  --from-literal=token=root
```

## 4. Déployer via ArgoCD

```bash
# Récupérer le mot de passe ArgoCD
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo

# Appliquer l'Ingress + App of Apps
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/argocd-app.yaml

# Vérifier la synchro
argocd login localhost:30080 --username admin --insecure
argocd app list
argocd app sync greenlogistics
```

## 5. Créer les topics Redpanda

```bash
kubectl -n messaging exec -it redpanda-0 -- rpk topic create gps.positions \
  --partitions 3 --replicas 1

kubectl -n messaging exec -it redpanda-0 -- rpk topic create gps.positions.dlq \
  --partitions 1 --replicas 1

kubectl -n messaging exec -it redpanda-0 -- rpk topic list
```

## 6. Installer Linkerd

```bash
brew install linkerd
linkerd check --pre
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check

# Injecter le sidecar dans le namespace app
kubectl annotate namespace app linkerd.io/inject=enabled
kubectl rollout restart deployment -n app
```

## 7. Port-forwards pour la démo

```bash
# Ouvrir dans des terminaux séparés AVANT la démo
kubectl port-forward -n argocd     svc/argocd-server         8080:443  &
kubectl port-forward -n monitoring svc/kps-grafana           9090:80   &
kubectl port-forward -n mail       svc/mailhog               8025:8025 &
kubectl port-forward -n kubecost   svc/kubecost-cost-analyzer 9091:9090 &
```

## 8. Vérification finale

```bash
kubectl get pods -A | grep -v -E "Running|Completed"
# Doit être vide

kubectl top nodes
# Vérifier la consommation RAM < 85%
```

## Nettoyage (après soutenance)

```bash
kind delete cluster --name greenlogistics
docker system prune -a --volumes
```
