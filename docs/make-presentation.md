# 🎤 Aide-mémoire `make` — Soutenance GreenLogistics

Toutes les commandes à connaître le jour de la présentation, dans l'ordre du déroulé.
Contexte cluster : `kind-greenlogistics` · namespace applicatif : `app`.

> 💡 `make help` liste toutes les cibles à tout moment.

---

## 🔑 Accès aux interfaces (à ouvrir avant de commencer)

Chaque commande ouvre un **tunnel qui bloque le terminal** → lance-la dans un onglet dédié (`Ctrl-C` pour fermer).

| Commande | Interface | URL | Identifiants |
|---|---|---|---|
| `make grafana` | Grafana (dashboards) | http://localhost:9090 | `admin` / `prom-operator` |
| `make prometheus` | Prometheus (métriques, PromQL) | http://localhost:9091 | — |
| `make alertmanager` | Alertmanager (alertes actives) | http://localhost:9093 | — |
| `make mailhog` | MailHog (mails d'alerte reçus) | http://localhost:8025 | — |
| `make vault` | Vault (secrets, mode dev) | http://localhost:8200 | token : `root` |
| `make loki` | Loki (logs, API) | http://localhost:3100 | via Grafana › Explore |
| `make argocd-ui` | ArgoCD (GitOps) | https://localhost:8080 | `admin` / `yvSQvc2Z9dbNv8bX` |

> ⚠️ ArgoCD est en HTTPS auto-signé → le navigateur affiche un avertissement, « continuer quand même ».
> Grafana et ArgoCD sont aussi exposés en direct via kind : http://localhost:30090 et https://localhost:30080.

---

## 1️⃣ Point de départ — état du cluster

```bash
make status      # pods du namespace app + applications ArgoCD (Synced/Healthy)
```

*À dire :* « 7 applications ArgoCD synchronisées, tous les pods Running — le cluster est piloté par GitOps. »

---

## 2️⃣ Qualité du code — tests & lint (sans cluster)

```bash
make test        # tous les tests unitaires (Python + Node)
make lint        # ruff (Python) + eslint (Node) sur les 4 services
```

*Cibles fines si besoin :* `make test-py`, `make test-node`, `make lint-py`, `make lint-node`.

*À dire :* « Ce sont exactement les mêmes étapes que la CI GitHub Actions exécute sur chaque push. »

---

## 3️⃣ Démonstration fonctionnelle de l'application

```bash
make smoke                    # test e2e via l'Ingress : front + CRUD colis
make seed                     # injecte 3 colis de démo + trajets GPS (dashboards non vides)
make demo                     # scénario complet : crée un colis OUT_FOR_DELIVERY + trajet GPS
make simulate PARCEL=<id>     # rejoue un trajet GPS pour un colis donné
```

*Déroulé suggéré :* `make seed` (pour peupler) → montrer le front → `make demo` (colis live) → montrer le suivi GPS en temps réel dans l'UI.

*Reset si besoin :* `make seed-clean` puis `make seed`.

---

## 4️⃣ Observabilité — le cœur de la démo

**Montrer que tout est mesuré :**

```bash
make grafana       # dashboards : trafic, latence, taux d'erreur, SLO / Error Budget
make prometheus    # Status › Targets (services scrapés) · Graph (PromQL) · Alerts
```

Requêtes PromQL utiles à taper en direct dans Prometheus :

```promql
up                                          # cibles scrapées (doivent être à 1)
slo:parcel_api:error_rate:ratio5m           # taux d'erreur SLO (recording rule)
slo:parcel_api:error_budget_remaining       # budget d'erreur restant
slo:parcel_api:latency_p95:5m               # latence P95
```

*À dire :* « Les SLO sont définis en tant que recording rules : taux d'erreur < 1 %, latence P95 < 200 ms. »

---

## 5️⃣ Alerting de bout en bout — l'envoi de mail

**La chaîne à raconter :**
`parcel-api /metrics` → **Prometheus** (règle `SLOErrorRateBreach` si 5xx > 1 % pendant 2 min) → **Alertmanager** (route `team=greenlogistics`) → **MailHog** (mail sur `oncall@greenlogistics.local`).

**Option A — scénario clé-en-main (recommandé) :**

```bash
make mon-demo        # baseline → coupe PostgreSQL → attend l'alerte → vérifie le mail → répare
```

Une seule commande déroule toute la chaîne (~3 min) et affiche à la fin le taux d'erreur, l'alerte `firing` et le mail reçu. PostgreSQL est **toujours réparé automatiquement** en sortie, même si tu interromps (Ctrl-C).

**Option B — étape par étape (pour commenter en direct) :**

```bash
make mon-status      # état complet : targets scrapées, taux d'erreur SLO, alertes, mails
make mon-load        # 1. trafic sain → error budget à 100 %
make mon-break       # 2. coupe PostgreSQL + envoie du trafic → 5xx
# … patienter ~2 min (l'alerte a un `for: 2m`) …
make mon-errors      # 3. le taux d'erreur dépasse 1 %, l'alerte passe "firing"
make mon-alerts      # 4. SLOErrorRateBreach = firing dans Alertmanager
make mon-mail        # 5. le mail « Taux d'erreur parcel-api dépasse 1% » est arrivé
make mon-heal        # 6. répare PostgreSQL + réactive l'auto-sync ArgoCD
```

**En parallèle, garder les UIs ouvertes** pour montrer visuellement :

```bash
make alertmanager    # onglet Alertmanager : l'alerte passe en "firing"
make mailhog         # boîte MailHog : le mail arrive en direct
```

*À dire :* « Quand le SLO est violé, une alerte critique part automatiquement par mail à l'astreinte — ici simulé par MailHog. Je coupe la base de données, et sans rien faire d'autre, l'alerte se déclenche et le mail arrive. »

> ⚙️ Détail technique à mentionner si on te pose la question : la panne coupe le StatefulSet PostgreSQL ; comme ArgoCD a le self-heal actif, le script suspend temporairement l'auto-sync de l'app `infra` puis le réactive à la réparation — d'où le retour automatique à l'état sain.

---

## 6️⃣ Sécurité & GitOps

```bash
make vault         # secrets centralisés ; DATABASE_URL synchronisé vers K8s via External Secrets
make argocd-ui     # arbre des 7 applications, self-heal & prune activés
```

*À dire :* « Aucun secret en clair dans Git : Vault est la source, External Secrets Operator synchronise. ArgoCD réconcilie l'état réel avec le Git en continu. »

---

## 🛟 Diagnostic en direct (si un souci survient)

```bash
make logs SVC=parcel-api      # logs live d'un service (SVC = parcel-api | gps-ingestor | notifier | tracker-front)
make status                   # re-vérifier pods + applications
make wait                     # attendre que tous les pods du namespace app soient Ready
```

---

## ⚙️ Cycle de vie du cluster (avant / après)

```bash
make cluster-up      # crée le cluster kind s'il n'existe pas
make cluster-down    # supprime le cluster (à la fin de la démo)
```

---

## 📋 Ordre conseillé le jour J

1. **Avant l'oral** : `make cluster-up` (si besoin) → `make status` → `make seed` → ouvrir les onglets `make grafana`, `make argocd-ui`.
2. **Intro** : `make status` (GitOps en action).
3. **Qualité** : `make test` / `make lint` (miroir de la CI).
4. **App** : `make demo` + front + suivi GPS.
5. **Observabilité** : Grafana + Prometheus (SLO).
6. **Alerting** : provoquer l'erreur → `make alertmanager` → `make mailhog` (le mail !).
7. **Sécurité/GitOps** : `make vault` + `make argocd-ui`.
