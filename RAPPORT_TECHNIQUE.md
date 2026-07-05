# Rapport technique — GreenLogistics

> **Projet Final — Développer pour le Cloud (Master 2)** · v3 LOCAL-FIRST
> Sujet A — Tracking temps réel de livraison dernière mile
> Stack 100 % locale : kind · ArgoCD · Redpanda · HashiCorp Vault · Linkerd · kube-prometheus-stack · Kubecost

---

## 1. Contexte métier & persona

**GreenLogistics** est une startup de livraison écologique du dernier kilomètre. Le produit permet de **suivre des colis en temps réel**, de notifier le destinataire à l'approche du livreur, et d'offrir un dashboard d'exploitation.

| Persona | Besoin | KPI |
|---|---|---|
| **Destinataire** | Savoir quand son colis arrive | Notification « livraison imminente » fiable (< 5 min avant) |
| **Exploitant** | Suivre la flotte et la qualité de service | Taux d'erreur API < 1 %, latence P95 < 200 ms |
| **Équipe plateforme** | Déployer sans risque, observer, maîtriser les coûts | Déploiement GitOps, SLO tenus, coût/namespace visible |

Les domaines fonctionnels minimaux du Sujet A sont couverts :
1. **API de gestion de colis** (REST/HTTP) — création, statuts, recherche.
2. **Service d'ingestion de positions GPS** (événementiel) — un point toutes les 5 s par livreur (simulé).
3. **Service de notification** — événement « livraison à 5 min » vers le destinataire (email simulé MailHog).
4. **Front de suivi** — page publique de tracking d'un colis.

---

## 2. Architecture générale

### 2.1 Vue d'ensemble

Quatre microservices, chacun dans son propre conteneur, communiquant en synchrone (HTTP via Ingress NGINX) et en **asynchrone** (Redpanda, compatible Kafka). Le diagramme complet (Mermaid) est dans [`docs/architecture.md`](docs/architecture.md).

```
Client ──▶ Ingress NGINX (greenlogistics.local)
                │
     ┌──────────┼───────────────┬──────────────────┐
     ▼          ▼               ▼                  ▼
 tracker-front  parcel-api   gps-ingestor      (/api, /gps, /)
                   │             │
                   ▼             ▼  topic "gps-positions"
               PostgreSQL     Redpanda ──────────▶ notifier ──▶ MailHog (SMTP)
```

### 2.2 Les quatre services

| Service | Runtime | Rôle | Persistance / IO |
|---|---|---|---|
| `parcel-api` | **Python 3.12 / FastAPI** | CRUD colis, statuts, événements de livraison | PostgreSQL (asyncpg) |
| `gps-ingestor` | **Python 3.12 / FastAPI** | Ingestion des points GPS, publication événementielle | Producteur Redpanda |
| `notifier` | **Node.js 20 / Express** | Consomme les positions, calcule la distance (haversine), notifie à l'approche | Consommateur Redpanda → MailHog |
| `tracker-front` | **React / Vite → NGINX** | SPA publique de suivi d'un colis | Appelle `parcel-api` via l'Ingress |

> **Note d'honnêteté** : `parcel-api` et `gps-ingestor` ont été **migrés de Node.js vers Python/FastAPI** en cours de projet (meilleure ergonomie pour l'API async et l'exposition Prometheus via `prometheus_client`). `notifier` et `tracker-front` restent en Node. Les artefacts Node morts de l'ancienne implémentation ont été purgés du dépôt.

### 2.3 Communication asynchrone (bloc 4.1)

- **Broker** : Redpanda (StatefulSet, namespace `messaging`).
- **Topic** : `gps-positions` — `gps-ingestor` produit, `notifier` consomme (1 topic + 1 souscription minimum ✅).
- **Découplage** : le pic de charge GPS (haute fréquence) n'impacte pas l'API de colis.

### 2.4 Persistance managée (bloc 4.1)

- **PostgreSQL 16** en StatefulSet + PVC (namespace `app`), service headless.
- Schéma relationnel : `parcels` (colis + coordonnées destinataire) et `delivery_events` (audit des transitions de statut). Migrations exécutées au démarrage du service (`run_migrations` dans le lifespan FastAPI).

---

## 3. Choix techniques (ADR)

Les décisions structurantes sont formalisées dans [`ADR.md`](ADR.md) :

| ADR | Décision | Raison clé |
|---|---|---|
| ADR-001 | **Redpanda** comme broker | API Kafka standard, plus léger que Kafka (pas de ZooKeeper), DLQ native |
| ADR-002 | **PostgreSQL** StatefulSet | Données structurées (colis/statuts), UUID natif |
| ADR-003 | **Linkerd** plutôt qu'Istio | mTLS auto, ~400 Mo RAM vs ~1 Go pour Istio — critique en local |
| ADR-004 | **CI/CD pull-based** via ArgoCD | Évite d'exposer un kubeconfig du cluster local dans la CI |
| ADR-005 | **Vault + External Secrets** | Aucun secret en clair dans Git, rotation possible |

---

## 4. Couverture des exigences techniques

### 4.1 — Architecture & conception (25 pts)
- ✅ 4 microservices distincts, un conteneur chacun.
- ✅ Communication asynchrone Redpanda (topic + souscription).
- ✅ Persistance managée PostgreSQL.
- ✅ Diagramme d'architecture committé (Mermaid, `docs/architecture.md`).
- ✅ `ADR.md` — 5 décisions (Contexte / Décision / Conséquences).

### 4.2 — Conteneurisation & runtime (15 pts)
- ✅ **Dockerfile multi-stage** par service (builder + runner), utilisateur non-root, `HEALTHCHECK`.
  - Python : `python:3.12-slim` (builder pip → runner). Node : `node:20-alpine`. Front : build Vite → `nginx:alpine`.
- ✅ Images publiées sur **GHCR** (`ghcr.io/<owner>/greenlogistics/<service>`).
- ✅ **HPA** sur `parcel-api` (CPU 70 % / mémoire 80 %, 2→6 replicas) et `gps-ingestor` (CPU 60 %, 2→10 replicas), via `metrics-server`.
- ✅ `requests` / `limits` sur tous les pods applicatifs.
- ⚠️ **Point d'amélioration** : les images sont taguées par SHA de commit + `latest`. L'ajout d'un **tag sémantique** (`vX.Y.Z`) sur release est identifié comme amélioration (cf. §7).

### 4.3 — Infrastructure-as-Code (10 pts)
- ✅ **Terraform** provisionne la plateforme : namespaces + RBAC, ArgoCD, kube-prometheus-stack, Vault, Loki, Promtail, Redpanda, Argo Rollouts, External Secrets Operator, Linkerd (via `null_resource` + script).
- ✅ **State versionné** en local (`terraform/state/terraform.tfstate`).
- ✅ **Module réutilisable maison** : `modules/namespace-rbac` (création de namespaces + ServiceAccount + Role/RoleBinding `secret-reader`).
- Providers : `hashicorp/kubernetes`, `hashicorp/helm`, `hashicorp/null`.

### 4.4 — CI/CD sécurisé (15 pts)
- ✅ Pipeline **GitHub Actions** (`.github/workflows/ci.yaml`), matrice sur les 4 services :
  1. **Lint + tests** (Python : `ruff` + `pytest` ; Node : `eslint` + `jest`/`vitest`).
  2. **Build & push** multi-arch (amd64/arm64) sur GHCR.
  3. **Scan CVE Trivy** : rapport SARIF (HIGH+CRITICAL) uploadé + **échec du job si CVE `CRITICAL` corrigeable** (`--exit-code 1 --severity CRITICAL --ignore-unfixed`).
  4. Job `update-manifests` : réécrit le tag d'image (SHA) dans `k8s/*/deployment.yaml` et commite `[skip ci]`.
- ✅ **Pattern pull-based** (ADR-004) : la CI ne touche pas au cluster ; **ArgoCD** tire le changement de tag et déploie. Aucun kubeconfig exposé dans la CI.
- ✅ **Secrets hors Git** : Vault (dev-mode) + External Secrets Operator synchronisant vers un `Secret` K8s.

### 4.5 — GitOps & déploiement progressif (10 pts)
- ✅ **ArgoCD** installé, pattern **App of Apps** : la racine `greenlogistics` (`k8s/argocd-app.yaml`) déploie les Applications enfants (`k8s/apps/` : `infra`, `parcel-api`, `gps-ingestor`, `notifier`, `tracker-front`, **`monitoring`**).
- ✅ **Self-Heal** activé (`syncPolicy.automated.selfHeal: true`, `prune: true`) — démontrable en live (scale à 0 → resync automatique).
- ✅ **Canary** : `parcel-api` déployé en **Argo Rollouts** (`k8s/parcel-api/rollout.yaml`) avec montée en charge progressive.

### 4.6 — Observabilité & SRE (15 pts)
- ✅ **kube-prometheus-stack** (Prometheus + Grafana + Alertmanager).
- ✅ **Loki + Promtail** — logs centralisés.
- ✅ **`/metrics`** exposé par `parcel-api` et `gps-ingestor` (`prometheus_client`), scrapés via **ServiceMonitor** (`k8s/monitoring/servicemonitors.yaml`).
- ✅ **2 SLO en Recording Rules** (`k8s/monitoring/recording-rules.yaml`) :
  - **SLO 1** — taux d'erreur `parcel-api` < 1 % (`slo:parcel_api:error_rate:ratio5m`).
  - **SLO 2** — latence P95 `parcel-api` < 200 ms (`slo:parcel_api:latency_p95:5m`).
  - + **Error Budget** (`slo:parcel_api:error_budget_remaining`).
- ✅ **Dashboard Grafana custom** (`k8s/monitoring/grafana-dashboard.yaml`, auto-importé par le sidecar) : taux d'erreur, latence P95/P99, Error Budget, débit par route.
- ✅ **Alerte active → MailHog** : `SLOErrorRateBreach` / `SLOLatencyP95Breach` routées par un `AlertmanagerConfig` (`k8s/monitoring/alertmanager-mailhog.yaml`) vers MailHog (SMTP `mailhog.mail:1025`). Chaîne vérifiée de bout en bout (email `[FIRING]` reçu dans MailHog).

### 4.7 — Sécurité (DevSecOps) (10 pts)
- ✅ **Trivy** : échec du build si CVE `CRITICAL` corrigeable (cf. 4.4).
- ✅ **Network Policies** deny-by-default dans le namespace `app` (`k8s/infra/networkpolicies.yaml`) : `default-deny-all` + allow-lists explicites par service (parcel-api ↔ postgres, gps-ingestor → messaging, notifier → messaging/parcel-api/mail) + `allow-metrics-scrape` (monitoring → /metrics).
- ✅ **mTLS automatique** via **Linkerd** (injection par annotation de namespace).
- ✅ **Identité service-à-service** : ServiceAccount + Role/RoleBinding (`module namespace-rbac`).

### 4.8 — FinOps / RessourceOps (5 pts)
- ✅ **Kubecost** déployé (namespace `kubecost`), dashboard accessible → coût/consommation par namespace.
- ✅ **Labels** `team`, `env`, `app` sur les ressources K8s (services, netpols, namespaces).
- Capture du rapport Kubecost par namespace à inclure dans `docs/captures/` (cf. §6).

### 4.9 — Bonus
- Pistes : Chaos Mesh, tracing Tempo/OpenTelemetry, suite e2e dans la CI (non prioritaires, cf. §7).

---

## 5. Difficultés rencontrées & résolutions

> Section volontairement transparente — les incidents ci-dessous ont été diagnostiqués et corrigés sur le cluster.

### 5.1 Prometheus en CrashLoopBackOff (OOMKilled) — **incident majeur**
- **Symptôme** : après ~9 jours d'uptime, le pod Prometheus était `1/2 Running`, **196 redémarrages**. Grafana et toute requête PromQL renvoyaient « connection refused ».
- **Diagnostic** : `lastState.reason = OOMKilled`, `exitCode 137`. Prometheus démarrait (« Server is ready ») puis dépassait sa **limite mémoire de 512 Mi** au chargement du WAL (253 segments accumulés) + rule manager.
- **Correction** : limite portée à **1 Gi** (requests 256→512 Mi) dans `terraform/main.tf`, appliquée immédiatement via patch de la CR Prometheus. Pod stable, 0 redémarrage depuis.
- **Leçon** : sur un cluster local longue-durée, dimensionner Prometheus selon la croissance du WAL, pas seulement la charge instantanée.

### 5.2 Aucune métrique applicative dans Prometheus
- **Symptôme** : `http_requests_total` absent de Prometheus ; SLO et dashboard vides malgré `/metrics` exposé.
- **Diagnostic** : (1) **aucun `ServiceMonitor`** pour les services applicatifs — l'opérateur Prometheus ignore les annotations `prometheus.io/scrape`. (2) La Network Policy `default-deny-all` **bloquait l'ingress** du scrape monitoring → app.
- **Correction** : ajout de 2 ServiceMonitors (label `release: kps`, `jobLabel: app`) + Network Policy `allow-metrics-scrape` autorisant le namespace `monitoring`.

### 5.3 Recording rules SLO vides / erronées
- **Bug 1** : `sum(rate(erreurs))` renvoie *vide* (et non 0) en l'absence de 5xx → SLO et Error Budget illisibles. Corrigé par `... or on() vector(0)`.
- **Bug 2** : `histogram_quantile(0.95, rate(bucket))` sans agrégation → quantile par série. Corrigé en `histogram_quantile(0.95, sum by (le) (rate(...)))`.
- **Résultat** : taux d'erreur **0 %**, P95 **≈ 5 ms**, Error Budget **100 %**.

### 5.4 ExternalSecret `Degraded`
- **Symptôme** : l'app ArgoCD `infra` restait `Degraded`.
- **Cause** : le secret Vault `secret/greenlogistics/api` n'existait pas (Vault dev-mode **réinitialisé** au redémarrage du pod — cf. ADR-005).
- **Correction** : re-provisionnement (`vault kv put …`). **Procédure à rejouer** après tout redémarrage de Vault (documentée dans `SETUP.md` / `PLAN.md`).

### 5.5 Dette de migration Node → Python
- Artefacts `.js` morts et `package.json` Node subsistaient dans les services Python, ainsi que des `__pycache__` trackés. **34 fichiers purgés** pour lever l'ambiguïté de runtime.

---

## 6. Résultats & preuves

État du cluster à la rédaction :
- **ArgoCD** : 6 applications `Synced / Healthy` (App of Apps).
- **SLO** `parcel-api` : erreur 0 %, P95 ≈ 5 ms, Error Budget 100 %.
- **HPA** actifs (parcel-api 2/6, gps-ingestor 2/10).
- **Alerte** de test livrée dans MailHog (`[FIRING:1] … (critical greenlogistics)`).
- **Prometheus** stable, cibles `parcel-api` / `gps-ingestor` `up`.

Captures à déposer dans `docs/captures/` :
1. ArgoCD — vue App of Apps tout `Synced/Healthy`.
2. Grafana — dashboard « GreenLogistics — SLO parcel-api ».
3. GitHub Actions — pipeline vert (build/test/scan des 4 services).
4. Kubecost — coût par namespace.
5. MailHog — email d'alerte / de notification reçu.

---

## 7. Pistes d'amélioration

- **Tags sémantiques** d'images sur release (`vX.Y.Z`) en plus du SHA.
- **Endpoint `/metrics`** sur `notifier` (worker) pour un SLO de consommation d'événements.
- **SLO multi-fenêtres** (burn-rate alerting) plutôt qu'un simple seuil.
- **Bonus** : Chaos Mesh (expérience de panne), tracing distribué Tempo + OpenTelemetry, suite e2e (Playwright/k6) dans la CI.
- **Persistance Vault** (mode non-dev) pour éviter le re-provisionnement des secrets.

---

## 8. Reproductibilité

Le cluster complet se reconstruit sur une machine tierce en < 30 min (cf. [`SETUP.md`](SETUP.md)) :
1. `kind create cluster --config kind-config.yaml`
2. `cd terraform && terraform init && terraform apply -auto-approve`
3. Provisionner le secret Vault (`vault kv put secret/greenlogistics/api …`).
4. `kubectl apply -f k8s/argocd-app.yaml` → ArgoCD déploie tout le reste (App of Apps).

---

*Rapport rédigé pour la soutenance du 6 juillet 2026 — équipe GreenLogistics.*
