# Architecture GreenLogistics

## Diagramme global

```mermaid
graph TB
    subgraph Internet
        Client[Navigateur / Client HTTP]
    end

    subgraph kind-cluster["Cluster kind (3 nœuds)"]
        subgraph ingress["ingress-nginx"]
            ING[Ingress\ngreenlogistics.local]
        end

        subgraph ns_app["namespace: app (Linkerd mTLS)"]
            PA[parcel-api\n:3000]
            GI[gps-ingestor\n:3001]
            TF[tracker-front\n:3002]
            NT[notifier\n:3003]
        end

        subgraph ns_data["namespace: app — données"]
            PG[(PostgreSQL\nStatefulSet)]
        end

        subgraph ns_msg["namespace: messaging"]
            RP[[Redpanda\nKafka-compatible]]
        end

        subgraph ns_mail["namespace: mail"]
            MH[MailHog\nSMTP + UI]
        end

        subgraph ns_infra["namespace: argocd / monitoring / vault"]
            ARGOCD[ArgoCD]
            PROM[Prometheus + Grafana]
            VAULT[HashiCorp Vault]
            LOKI[Loki + Promtail]
            ESO[External Secrets Operator]
        end
    end

    subgraph gitops["GitHub (distant)"]
        GHCR[(GHCR\nImages)]
        REPO[greenlogistics-gitops\nrép. GitOps]
    end

    Client --> ING
    ING -->|/api/parcels| PA
    ING -->|/api/positions| GI
    ING -->|/track| TF

    PA --> PG
    GI -->|publish gps.positions| RP
    RP -->|consume gps.positions| NT
    NT -->|GET/PATCH /parcels| PA
    NT -->|SMTP| MH
    TF -->|GET /parcels| PA

    NT -->|DLQ gps.positions.dlq| RP

    ARGOCD -->|pull sync| REPO
    VAULT --> ESO
    ESO -->|K8s Secret api-secret| PA

    PROM -.->|scrape /metrics| PA
    PROM -.->|scrape /metrics| GI
    LOKI -.->|collect logs| NT
```

## Flux de données principal

```
Client mobile
    │
    ▼ POST /api/positions/{parcelId}
gps-ingestor
    │ publish → gps.positions (Kafka/Redpanda)
    ▼
notifier (consumer group: notifier-group)
    │ GET /parcels/{id}  (parcel-api)
    │ haversine distance < 2000m ?
    │   └─ OUI → envoi email MailHog
    │            PATCH /parcels/{id}/status (OUT_FOR_DELIVERY → DELIVERING)
    │   distance < 100m ?
    │   └─ OUI → PATCH status → DELIVERED
    │
    └─ Erreur (3 retries) → DLQ gps.positions.dlq
```

## SLOs

| SLO | Cible | Alerte PrometheusRule |
|-----|-------|----------------------|
| Taux d'erreur HTTP | < 1% | `SLOErrorRateBreach` |
| Latence P95 | < 200ms | `SLOLatencyP95Breach` |

## Canary — Argo Rollouts

```
Déploiement parcel-api
  │
  ├── 20% canary  ──(2 min)──▶ 50% ──(2 min)──▶ 100%
  │                              │
  │                        AnalysisRun
  │                    (success rate ≥ 99%)
  └── abort si analyse KO
```
