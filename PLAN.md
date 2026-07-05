# Plan restant — GreenLogistics TP Final

> Soutenance **7 juillet 2026** · Stack : kind · ArgoCD · Redpanda · Vault · Linkerd

---

## État des lieux

| Composant | Manifests/Code | Sur le cluster |
|---|---|---|
| CI GitHub Actions | ✅ complet | ⏳ pas encore pushé |
| ArgoCD App of Apps | ✅ complet | ⏳ cluster inexistant |
| Terraform (ArgoCD, Prometheus, Vault, Loki, Redpanda) | ✅ complet | ⏳ non appliqué |
| kind-config.yaml (3 nœuds) | ✅ complet | ⏳ cluster inexistant |
| Manifests k8s (deployments, services, HPA, rollout…) | ✅ complet | ⏳ non pushés |
| Prometheus recording rules | ✅ complet | ⏳ non appliquées |
| docs/architecture.md | ✅ complet | — |
| Ingress NGINX | ❌ absent de Terraform | ⏳ |
| Linkerd | ❌ absent de Terraform | ⏳ |
| Argo Rollouts | ❌ absent de Terraform | ⏳ |
| External Secrets Operator | ❌ absent de Terraform | ⏳ |
| RAPPORT_TECHNIQUE.md | ❌ manquant | — |
| Slides soutenance | ❌ manquant | — |
| Captures d'écran | ❌ manquant | — |

---

## Phase 1 — Pousser le code (15 min) · **À faire en premier**

- [ ] Commiter et pusher tous les fichiers modifiés
  ```bash
  git add .github/workflows/ci.yaml k8s/ services/notifier/package-lock.json PLAN.md
  git commit -m "feat: monorepo gitops, ArgoCD App of Apps, fix image refs"
  git push
  ```
- [ ] Vérifier sur GitHub → Actions que les **4 jobs `build-test-scan`** passent au vert
- [ ] Vérifier que le job **`update-manifests`** commite les tags SHA dans `k8s/*/deployment.yaml`

---

## Phase 2 — Cluster local (30 min)

- [ ] Créer le cluster kind 3 nœuds
  ```bash
  kind create cluster --config kind-config.yaml
  ```
- [ ] Provisionner la plateforme via Terraform
  ```bash
  cd terraform && terraform init && terraform apply -auto-approve
  ```
  > Installe : ArgoCD · kube-prometheus-stack · Vault (dev) · Loki · Promtail · Redpanda
- [ ] Vérifier tous les pods en Running
  ```bash
  kubectl get pods -A
  ```

---

## Phase 3 — Composants manquants dans Terraform (45 min)

Ces 4 outils **ne sont pas dans `terraform/main.tf`** — installation manuelle requise.

- [ ] **Ingress NGINX**
  ```bash
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
    --set controller.hostPort.enabled=true
  ```

- [ ] **Linkerd**
  ```bash
  linkerd install --crds | kubectl apply -f -
  linkerd install | kubectl apply -f -
  linkerd check
  ```

- [ ] **Argo Rollouts**
  ```bash
  kubectl create namespace argo-rollouts
  kubectl apply -n argo-rollouts \
    -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
  ```

- [ ] **External Secrets Operator**
  ```bash
  helm repo add external-secrets https://charts.external-secrets.io
  helm install external-secrets external-secrets/external-secrets \
    -n external-secrets --create-namespace
  ```

---

## Phase 4 — Bootstrap application (30 min)

- [ ] Provisionner les secrets dans Vault
  ```bash
  kubectl -n vault exec -it vault-0 -- \
    vault kv put secret/greenlogistics/api \
    database_url="postgresql://gluser:changeme@postgres.app.svc.cluster.local:5432/greenlogistics"
  ```
- [ ] Créer le secret `vault-token` pour ESO
  ```bash
  kubectl create secret generic vault-token \
    -n external-secrets --from-literal=token=root
  ```
- [ ] Appliquer la root app ArgoCD
  ```bash
  kubectl apply -f k8s/argocd-app.yaml
  ```
- [ ] Vérifier ArgoCD — toutes les apps **Synced / Healthy**
  ```bash
  # port-forward si pas d'ingress encore
  kubectl port-forward -n argocd svc/argocd-server 8080:443
  # https://localhost:8080 · user: admin
  ```
- [ ] Ajouter `greenlogistics.local` dans `/etc/hosts`
  ```bash
  echo "127.0.0.1 greenlogistics.local" | sudo tee -a /etc/hosts
  ```

---

## Phase 5 — Validation end-to-end (30 min)

- [ ] Créer un colis et le passer en `OUT_FOR_DELIVERY`
  ```bash
  PARCEL_ID=$(curl -s -X POST http://greenlogistics.local/api/parcels \
    -H "Content-Type: application/json" \
    -d '{"senderName":"Alice","recipientName":"Bob","recipientEmail":"bob@test.com",
         "recipientAddress":"12 rue de la Paix, Paris","recipientLat":48.8698,"recipientLng":2.3322}' \
    | jq -r '.id')

  curl -X PATCH http://greenlogistics.local/api/parcels/$PARCEL_ID/status \
    -H "Content-Type: application/json" -d '{"status":"OUT_FOR_DELIVERY"}'
  ```
- [ ] Lancer la simulation GPS
  ```bash
  bash services/gps-ingestor/scripts/simulate.sh $PARCEL_ID
  ```
- [ ] Vérifier l'email dans MailHog → `http://localhost:8025`
  ```bash
  kubectl port-forward -n mail svc/mailhog 8025:8025
  ```
- [ ] Vérifier tracker-front → `http://greenlogistics.local/track`

---

## Phase 6 — Observabilité (20 min)

- [ ] Appliquer les recording rules Prometheus
  ```bash
  kubectl apply -f k8s/monitoring/recording-rules.yaml
  ```
- [ ] Grafana — ajouter datasource Loki
  - URL : `http://loki.monitoring.svc.cluster.local:3100`
  - Accès Grafana : `http://localhost:30090`
- [ ] Grafana — importer dashboard **FastAPI Observability** (ID `17819`)
- [ ] Vérifier métriques et logs en temps réel durant la simulation GPS

---

## Phase 7 — Démos soutenance (répéter avant J7)

- [ ] **Self-Heal ArgoCD** (~90 sec)
  ```bash
  kubectl scale deploy/parcel-api -n app --replicas=0
  # ArgoCD resynce automatiquement → observer dans l'UI
  ```
- [ ] **Canary Rollout** (Argo Rollouts)
  ```bash
  kubectl apply -f k8s/parcel-api/rollout.yaml
  kubectl argo rollouts get rollout parcel-api -n app --watch
  ```
- [ ] **HPA — autoscaling gps-ingestor**
  ```bash
  kubectl get hpa -n app -w
  ```
- [ ] **Kubecost** — coût par namespace
  ```bash
  helm repo add cost-analyzer https://kubecost.github.io/cost-analyzer
  helm install kubecost cost-analyzer/cost-analyzer -n kubecost --create-namespace
  kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9091:9090
  ```

> **Conseil** : enregistrer une vidéo de 60–90 s de chaque démo — plan B si le cluster crashe en live.

---

## Phase 8 — Livrable final (avant J7)

- [ ] `RAPPORT_TECHNIQUE.md` — 8 à 15 pages
  - Architecture · choix techniques · ADR · difficultés · résultats
- [ ] Slides soutenance → `docs/soutenance.pdf`
  - 25 min : 5 min archi · 10 min démo live · 5 min retex · 5 min Q&A
- [ ] Captures d'écran → `docs/captures/`
  - ArgoCD Synced · Dashboard Grafana · Pipeline CI vert · Kubecost par namespace
- [ ] Tag git de la version soutenue
  ```bash
  git tag v1.0-soutenance && git push --tags
  ```
- [ ] Vérifier accès lecture formateur — `abconsulting113@gmail.com`
