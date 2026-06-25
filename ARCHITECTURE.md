# GreenLogistics — Architecture Technique

> Plan de développement des 4 microservices · TP Final M2 · Stack LOCAL-FIRST

---

## 1. Structure du dépôt

```
greenlogistics/
├── services/
│   ├── parcel-api/          # REST CRUD colis + PostgreSQL
│   ├── gps-ingestor/        # Ingestion positions GPS → Redpanda
│   ├── notifier/            # Worker Redpanda → alertes MailHog
│   └── tracker-front/       # API publique de suivi
├── k8s/
│   ├── namespaces.yaml
│   ├── parcel-api/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── hpa.yaml
│   │   ├── networkpolicy.yaml
│   │   └── rollout.yaml     # Argo Rollouts canary
│   ├── gps-ingestor/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── hpa.yaml         # HPA — service le plus sollicité
│   ├── notifier/
│   │   └── deployment.yaml
│   ├── tracker-front/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── postgres/
│   │   ├── statefulset.yaml
│   │   └── service.yaml
│   └── externalsecret.yaml
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── modules/
│   │   └── namespace-rbac/  # module réutilisable maison
│   └── state/               # terraform.tfstate (branche tf-state)
├── docs/
│   ├── architecture.md      # diagramme Mermaid
│   └── captures/
├── .github/
│   └── workflows/
│       └── ci.yaml
├── kind-config.yaml
├── ADR.md
├── RAPPORT_TECHNIQUE.md
├── SETUP.md
└── README.md
```

---

## 2. Diagramme d'architecture (Mermaid)

```mermaid
graph TB
    subgraph "Namespace: app"
        PA[parcel-api<br/>:3000]
        GI[gps-ingestor<br/>:3001]
        NO[notifier<br/>worker]
        TF[tracker-front<br/>:3002]
        PG[(PostgreSQL<br/>StatefulSet)]
    end

    subgraph "Namespace: messaging"
        RP[Redpanda<br/>topic: gps.positions<br/>topic: gps.positions.dlq]
    end

    subgraph "Namespace: mail"
        MH[MailHog<br/>:1025 SMTP / :8025 UI]
    end

    GPS_SIM([GPS Simulator<br/>external]) -->|POST /positions| GI
    GI -->|produce| RP
    RP -->|consume| NO
    NO -->|SMTP| MH

    CLIENT([Client / Dashboard]) -->|GET /track/:code| TF
    TF -->|GET /parcels?trackingCode| PA
    PA <-->|SQL| PG

    ADMIN([Admin]) -->|CRUD /parcels| PA
```

---

## 3. Contrats d'interface

### 3.1 parcel-api — REST API

**Base URL** : `http://parcel-api.app.svc.cluster.local:3000`  
**Public** : via Ingress NGINX `http://greenlogistics.local/api`

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| `POST` | `/parcels` | Créer un colis |
| `GET` | `/parcels/:id` | Récupérer un colis par UUID |
| `GET` | `/parcels?trackingCode=GL-XXXX` | Recherche par code tracking |
| `PATCH` | `/parcels/:id/status` | Mettre à jour le statut |
| `GET` | `/health` | Health check (liveness/readiness) |
| `GET` | `/metrics` | Métriques Prometheus |

**POST /parcels — Body**
```json
{
  "senderName": "Jean Dupont",
  "recipientName": "Marie Martin",
  "recipientEmail": "marie@example.com",
  "recipientAddress": "12 rue de la Paix, 75001 Paris",
  "recipientLat": 48.8698,
  "recipientLng": 2.3322,
  "weightKg": 2.5
}
```

**Response 201**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "trackingCode": "GL-A3F7K2",
  "status": "PENDING",
  "createdAt": "2026-06-25T10:00:00Z"
}
```

**PATCH /parcels/:id/status — Body**
```json
{ "status": "OUT_FOR_DELIVERY" }
```

**Statuts valides** : `PENDING` → `IN_TRANSIT` → `OUT_FOR_DELIVERY` → `DELIVERED`

---

### 3.2 gps-ingestor — HTTP Ingestion

**Base URL** : `http://gps-ingestor.app.svc.cluster.local:3001`  
**Public** : via Ingress `http://greenlogistics.local/gps`

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| `POST` | `/positions` | Ingérer une position GPS |
| `GET` | `/health` | Health check |
| `GET` | `/metrics` | Métriques Prometheus |

**POST /positions — Body**
```json
{
  "deliveryId": "DEL-001",
  "parcelId": "550e8400-e29b-41d4-a716-446655440000",
  "latitude": 48.8566,
  "longitude": 2.3522,
  "speed": 25.5,
  "timestamp": "2026-06-25T14:30:00Z"
}
```

**Response 202**
```json
{ "accepted": true, "eventId": "evt-789xyz" }
```

> Le service publie immédiatement sur Redpanda et répond 202. Pas de stockage en base.

---

### 3.3 notifier — Worker Redpanda (pas d'API HTTP)

Service purement événementiel. Consomme `gps.positions`, exécute la logique de détection, envoie un email via MailHog.

**Logique de détection "5 min"** :
1. Récupérer les coordonnées destination du colis (via appel HTTP à `parcel-api`)
2. Calculer la distance entre la position GPS et la destination (formule Haversine)
3. Si distance < 2000 mètres ET statut = `OUT_FOR_DELIVERY` → envoyer notification
4. Mettre à jour statut du colis en `DELIVERED` si distance < 100 mètres

**Email envoyé**
```
Sujet : [GreenLogistics] Votre colis GL-A3F7K2 arrive dans ~5 min
Corps  : Bonjour Marie Martin, votre livreur est à proximité...
```

---

### 3.4 tracker-front — API publique

**Base URL** : `http://tracker-front.app.svc.cluster.local:3002`  
**Public** : via Ingress `http://greenlogistics.local/track`

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| `GET` | `/track/:trackingCode` | Suivi public d'un colis |
| `GET` | `/health` | Health check |

**Response 200**
```json
{
  "trackingCode": "GL-A3F7K2",
  "status": "OUT_FOR_DELIVERY",
  "statusLabel": "En cours de livraison",
  "recipient": "Marie Martin",
  "estimatedDelivery": "Aujourd'hui",
  "lastUpdate": "2026-06-25T14:32:00Z"
}
```

---

## 4. Schéma Redpanda (messages)

### Topic : `gps.positions`

```json
{
  "deliveryId": "string",
  "parcelId": "string (UUID)",
  "latitude": "number",
  "longitude": "number",
  "speed": "number (km/h)",
  "timestamp": "string (ISO 8601)"
}
```

### Topic : `gps.positions.dlq` (Dead Letter Queue)

Messages en erreur après 3 tentatives de traitement.

```json
{
  "originalMessage": { "...": "message original" },
  "errorReason": "string",
  "failedAt": "string (ISO 8601)",
  "attempt": "number"
}
```

**Configuration Redpanda recommandée** :
- Rétention : 24h
- Partitions : 3
- Replication factor : 1 (cluster single-broker local)

---

## 5. Schéma PostgreSQL

```sql
-- Exécuter au démarrage de parcel-api (migration)

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS parcels (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tracking_code  VARCHAR(20) UNIQUE NOT NULL,
    status         VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    sender_name    VARCHAR(255),
    recipient_name VARCHAR(255),
    recipient_email VARCHAR(255),
    recipient_address TEXT,
    recipient_lat  DECIMAL(10, 7),
    recipient_lng  DECIMAL(10, 7),
    weight_kg      DECIMAL(10, 2),
    notified_at    TIMESTAMP,           -- date de la notif "5 min"
    created_at     TIMESTAMP   NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP   NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS delivery_events (
    id         UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    parcel_id  UUID      NOT NULL REFERENCES parcels(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL,    -- STATUS_CHANGE, NOTIFICATION_SENT, etc.
    description TEXT,
    metadata   JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_parcels_tracking_code ON parcels(tracking_code);
CREATE INDEX idx_delivery_events_parcel ON delivery_events(parcel_id);
```

**Génération du tracking code** (à implémenter dans parcel-api) :
```
GL- + 6 caractères alphanumériques majuscules aléatoires
Exemple : GL-A3F7K2
```

---

## 6. Variables d'environnement

### parcel-api

| Variable | Valeur locale | Source |
|----------|---------------|--------|
| `PORT` | `3000` | ConfigMap |
| `DATABASE_URL` | `postgresql://gluser:***@postgres.app.svc:5432/greenlogistics` | Vault → ExternalSecret |
| `NODE_ENV` | `production` | ConfigMap |

### gps-ingestor

| Variable | Valeur locale | Source |
|----------|---------------|--------|
| `PORT` | `3001` | ConfigMap |
| `REDPANDA_BROKERS` | `redpanda.messaging.svc.cluster.local:9092` | ConfigMap |
| `TOPIC_GPS_POSITIONS` | `gps.positions` | ConfigMap |
| `TOPIC_DLQ` | `gps.positions.dlq` | ConfigMap |

### notifier

| Variable | Valeur locale | Source |
|----------|---------------|--------|
| `REDPANDA_BROKERS` | `redpanda.messaging.svc.cluster.local:9092` | ConfigMap |
| `TOPIC_GPS_POSITIONS` | `gps.positions` | ConfigMap |
| `CONSUMER_GROUP_ID` | `notifier-group` | ConfigMap |
| `PARCEL_API_URL` | `http://parcel-api.app.svc.cluster.local:3000` | ConfigMap |
| `SMTP_HOST` | `mailhog.mail.svc.cluster.local` | ConfigMap |
| `SMTP_PORT` | `1025` | ConfigMap |
| `NOTIFY_RADIUS_METERS` | `2000` | ConfigMap |

### tracker-front

| Variable | Valeur locale | Source |
|----------|---------------|--------|
| `PORT` | `3002` | ConfigMap |
| `PARCEL_API_URL` | `http://parcel-api.app.svc.cluster.local:3000` | ConfigMap |

---

## 7. Dockerfile template (multi-stage Node.js)

> À adapter pour chaque service. Remplacer `3000` par le port du service.

```dockerfile
# ── Stage 1 : dépendances de production ──────────────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

# ── Stage 2 : build (si TypeScript) ──────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY src ./src
COPY tsconfig.json ./
RUN npm run build

# ── Stage 3 : image finale ────────────────────────────────────────────────────
FROM node:20-alpine AS runner
RUN addgroup --system --gid 1001 nodejs \
 && adduser --system --uid 1001 --ingroup nodejs appuser

WORKDIR /app
COPY --from=deps    --chown=appuser:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:nodejs /app/dist         ./dist

USER appuser
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "dist/index.js"]
```

> **Objectif** : image finale < 250 Mo. Vérifier avec `docker images | grep greenlogistics`.

---

## 8. Structure de code par service

### 8.1 parcel-api

```
services/parcel-api/
├── src/
│   ├── index.ts            # démarrage Express/Fastify
│   ├── routes/
│   │   └── parcels.ts      # GET/POST/PATCH /parcels
│   ├── controllers/
│   │   └── parcelController.ts
│   ├── services/
│   │   └── parcelService.ts  # logique métier
│   ├── db/
│   │   ├── client.ts         # connexion PostgreSQL (pg ou prisma)
│   │   └── migrations.ts     # CREATE TABLE au démarrage
│   ├── metrics.ts            # prom-client — Counter erreurs, Histogram latence
│   └── health.ts             # GET /health
├── Dockerfile
├── package.json
└── tsconfig.json
```

**Dépendances npm** :
```json
{
  "dependencies": {
    "express": "^4.18.0",
    "pg": "^8.11.0",
    "prom-client": "^15.0.0",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "@types/express": "^4.17.0",
    "@types/pg": "^8.10.0",
    "jest": "^29.0.0"
  }
}
```

**Métriques Prometheus à exposer** :
```typescript
// src/metrics.ts
import client from 'prom-client';

export const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1]
});

export const httpRequestTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});
```

---

### 8.2 gps-ingestor

```
services/gps-ingestor/
├── src/
│   ├── index.ts
│   ├── routes/
│   │   └── positions.ts    # POST /positions
│   ├── kafka/
│   │   └── producer.ts     # KafkaJS producer vers Redpanda
│   ├── metrics.ts
│   └── health.ts
├── Dockerfile
└── package.json
```

**Dépendances npm** :
```json
{
  "dependencies": {
    "express": "^4.18.0",
    "kafkajs": "^2.2.0",
    "prom-client": "^15.0.0"
  }
}
```

**Pattern producer KafkaJS** :
```typescript
// src/kafka/producer.ts
import { Kafka } from 'kafkajs';

const kafka = new Kafka({
  clientId: 'gps-ingestor',
  brokers: [process.env.REDPANDA_BROKERS!]
});

const producer = kafka.producer();

export async function publishPosition(position: GpsPosition) {
  await producer.send({
    topic: process.env.TOPIC_GPS_POSITIONS!,
    messages: [{
      key: position.parcelId,
      value: JSON.stringify(position)
    }]
  });
}
```

---

### 8.3 notifier

```
services/notifier/
├── src/
│   ├── index.ts            # démarrage consumer + health HTTP minimaliste
│   ├── kafka/
│   │   └── consumer.ts     # KafkaJS consumer — groupe notifier-group
│   ├── handlers/
│   │   └── positionHandler.ts  # logique détection + email
│   ├── services/
│   │   ├── parcelClient.ts    # HTTP client → parcel-api
│   │   ├── mailer.ts          # Nodemailer → MailHog SMTP
│   │   └── haversine.ts       # calcul distance GPS
│   └── health.ts
├── Dockerfile
└── package.json
```

**Dépendances npm** :
```json
{
  "dependencies": {
    "kafkajs": "^2.2.0",
    "nodemailer": "^6.9.0",
    "axios": "^1.6.0"
  }
}
```

**Formule Haversine (distance entre deux coordonnées GPS)** :
```typescript
// src/services/haversine.ts
export function distanceMeters(
  lat1: number, lng1: number,
  lat2: number, lng2: number
): number {
  const R = 6371000; // rayon Terre en mètres
  const φ1 = lat1 * Math.PI / 180;
  const φ2 = lat2 * Math.PI / 180;
  const Δφ = (lat2 - lat1) * Math.PI / 180;
  const Δλ = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(Δφ/2) ** 2 + Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ/2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
```

**Logique handler** :
```typescript
// src/handlers/positionHandler.ts
export async function handlePosition(msg: GpsMessage) {
  const parcel = await parcelClient.getById(msg.parcelId);
  if (!parcel || parcel.status !== 'OUT_FOR_DELIVERY') return;
  if (parcel.notifiedAt) return; // déjà notifié

  const dist = distanceMeters(
    msg.latitude, msg.longitude,
    parcel.recipientLat, parcel.recipientLng
  );

  if (dist < 2000) {
    await mailer.sendNotification(parcel); // envoie l'email
    await parcelClient.patchStatus(msg.parcelId, 'OUT_FOR_DELIVERY'); // log notifiedAt
  }
  if (dist < 100) {
    await parcelClient.patchStatus(msg.parcelId, 'DELIVERED');
  }
}
```

---

### 8.4 tracker-front

```
services/tracker-front/
├── src/
│   ├── index.ts
│   ├── routes/
│   │   └── track.ts        # GET /track/:trackingCode
│   ├── services/
│   │   └── parcelClient.ts # HTTP → parcel-api
│   └── health.ts
├── Dockerfile
└── package.json
```

**Dépendances npm** :
```json
{
  "dependencies": {
    "express": "^4.18.0",
    "axios": "^1.6.0"
  }
}
```

---

## 9. Simulateur GPS (script de test)

> Créer dans `services/gps-ingestor/scripts/simulate.sh`  
> À lancer manuellement pour générer du trafic GPS pendant la démo.

```bash
#!/bin/bash
# Simule un livreur qui se rapproche de l'adresse de destination
# Utiliser avec : bash simulate.sh GL-A3F7K2 <parcelId>

PARCEL_ID=${2:-"replace-with-uuid"}
INGESTOR_URL="http://greenlogistics.local/gps"

# Coordonnées de départ (loin de la destination)
LAT=48.8400
LNG=2.3200

for i in $(seq 1 30); do
  # Approche progressive (simulation simple)
  LAT=$(echo "$LAT + 0.001" | bc)
  LNG=$(echo "$LNG + 0.0005" | bc)

  curl -s -X POST "$INGESTOR_URL/positions" \
    -H "Content-Type: application/json" \
    -d "{
      \"deliveryId\": \"DEL-DEMO-001\",
      \"parcelId\": \"$PARCEL_ID\",
      \"latitude\": $LAT,
      \"longitude\": $LNG,
      \"speed\": 22.5,
      \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    }"

  echo " → Position $i envoyée (lat: $LAT, lng: $LNG)"
  sleep 5
done
```

---

## 10. SLO définis (Recording Rules Prometheus)

### SLO 1 — Disponibilité parcel-api (taux d'erreur < 1%)

```yaml
# k8s/monitoring/recording-rules.yaml
groups:
  - name: greenlogistics.slo
    interval: 30s
    rules:
      - record: job:http_requests_total:rate5m
        expr: rate(http_requests_total[5m])

      - record: job:http_errors_total:rate5m
        expr: rate(http_requests_total{status_code=~"5.."}[5m])

      - record: slo:error_rate:ratio_rate5m
        expr: |
          job:http_errors_total:rate5m{job="parcel-api"}
          / job:http_requests_total:rate5m{job="parcel-api"}

      - alert: SLOErrorRateBreach
        expr: slo:error_rate:ratio_rate5m > 0.01
        for: 2m
        labels:
          severity: critical
          team: greenlogistics
        annotations:
          summary: "Taux d'erreur parcel-api > 1%"
```

### SLO 2 — Latence parcel-api P95 < 200ms

```yaml
      - record: slo:latency_p95:5m
        expr: |
          histogram_quantile(0.95,
            rate(http_request_duration_seconds_bucket{job="parcel-api"}[5m])
          )

      - alert: SLOLatencyBreach
        expr: slo:latency_p95:5m > 0.2
        for: 2m
        labels:
          severity: warning
          team: greenlogistics
        annotations:
          summary: "Latence P95 parcel-api > 200ms"
```

---

## 11. Labels K8s obligatoires (FinOps / Kubecost)

Tous les Deployments/StatefulSets doivent avoir ces labels :

```yaml
metadata:
  labels:
    app: parcel-api       # nom du service
    team: greenlogistics  # équipe
    env: production       # environnement
    version: "1.0.0"      # version sémantique
```

---

## 12. Ordre de démarrage des services

```
1. PostgreSQL StatefulSet      (dépendance de parcel-api)
2. Redpanda StatefulSet        (dépendance de gps-ingestor et notifier)
3. Vault + ExternalSecret      (dépendance de tous les services — secrets)
4. MailHog Deployment          (dépendance de notifier)
5. parcel-api Deployment       (dépendance de notifier et tracker-front)
6. gps-ingestor Deployment
7. notifier Deployment
8. tracker-front Deployment
```

> Dans ArgoCD App of Apps, utiliser les `sync-wave` annotations :
> - `argocd.argoproj.io/sync-wave: "0"` → infrastructure (postgres, redpanda, vault)
> - `argocd.argoproj.io/sync-wave: "1"` → middleware (mailhog)
> - `argocd.argoproj.io/sync-wave: "2"` → applications

---

## 13. Checklist de démarrage (J7-1)

- [ ] `git init` + créer repo `greenlogistics` public sur GitHub
- [ ] Créer repo `greenlogistics-gitops` public sur GitHub
- [ ] Copier `kind-config.yaml` → `kind create cluster --config kind-config.yaml`
- [ ] Vérifier : `kubectl get nodes` → 3 nodes Ready
- [ ] `mkdir -p services/{parcel-api,gps-ingestor,notifier,tracker-front}/src`
- [ ] `mkdir -p k8s/{parcel-api,gps-ingestor,notifier,tracker-front,postgres}`
- [ ] `mkdir -p terraform/modules/namespace-rbac`
- [ ] `mkdir -p docs/captures`
- [ ] Créer `ADR.md` avec les 3 premières ADRs
- [ ] Dessiner le diagramme Mermaid dans `docs/architecture.md` (section 2 ci-dessus)
- [ ] Premier commit : `git add . && git commit -m "feat: initial project structure"`
