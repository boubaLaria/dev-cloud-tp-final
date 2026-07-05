# Captures d'écran — soutenance GreenLogistics

Déposer ici les 5 captures attendues (bloc « Livrables » du sujet). Cluster **UP** requis.

| # | Fichier | Quoi capturer | Accès |
|---|---|---|---|
| 1 | `argocd-synced.png` | Les **6 applications `Synced / Healthy`** (App of Apps) | http://localhost:30080 — user `admin` / mdp `yvSQvc2Z9dbNv8bX` |
| 2 | `grafana-slo.png` | Dashboard **« GreenLogistics — SLO parcel-api »** (erreur, P95/P99, Error Budget) | http://localhost:30090 — user `admin` / mdp `prom-operator` |
| 3 | `ci-green.png` | Pipeline **GitHub Actions vert** (build/test/scan des 4 services) | GitHub → onglet **Actions** du dépôt |
| 4 | `kubecost-namespaces.png` | **Coût / consommation par namespace** | `kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9091:9090` → http://localhost:9091 |
| 5 | `mailhog-alert.png` | Email d'**alerte** (ou de notification livraison) reçu | `kubectl port-forward -n mail svc/mailhog 8025:8025` → http://localhost:8025 |

## Commandes utiles

```bash
# ArgoCD (NodePort déjà exposé par kind sur 30080) — sinon :
kubectl port-forward -n argocd svc/argocd-server 8080:443   # https://localhost:8080

# Grafana : NodePort 30090 exposé par kind. Dashboard directement :
#   http://localhost:30090/d/greenlogistics-slo

# Kubecost et MailHog : via port-forward (voir tableau ci-dessus)
```

> Astuce démo : générer un peu de trafic avant les captures pour animer les graphes —
> `for i in $(seq 1 200); do curl -s http://greenlogistics.local/api/parcels >/dev/null; done`
