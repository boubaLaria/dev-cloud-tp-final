#!/bin/bash
# Simule un livreur qui se rapproche de l'adresse de destination
# Usage: bash simulate.sh <parcelId>
# Exemple: bash simulate.sh 550e8400-e29b-41d4-a716-446655440000

PARCEL_ID=${1:?"Usage: $0 <parcelId>"}
# L'Ingress est exposé par kind sur le port hôte 8080 (containerPort 80 → hostPort 8080).
INGESTOR_URL="${INGESTOR_URL:-http://greenlogistics.local:8080/gps}"
INTERVAL=${INTERVAL:-5}

echo "Simulation GPS pour colis: $PARCEL_ID"
echo "Endpoint: $INGESTOR_URL/positions"
echo "Intervalle: ${INTERVAL}s"
echo "---"

# Coordonnées : départ loin, arrivée destination (Paris simulée)
# Destination: 48.8698, 2.3322 (Opéra, Paris)
LAT_START=48.8400
LNG_START=2.2800
LAT_END=48.8698
LNG_END=2.3322
STEPS=30

for i in $(seq 1 $STEPS); do
  # Interpolation linéaire vers la destination
  PROGRESS=$(echo "scale=6; $i / $STEPS" | bc)
  LAT=$(echo "scale=7; $LAT_START + ($LAT_END - $LAT_START) * $PROGRESS" | bc)
  LNG=$(echo "scale=7; $LNG_START + ($LNG_END - $LNG_START) * $PROGRESS" | bc)

  RESP=$(curl -s -w "\n%{http_code}" -X POST "$INGESTOR_URL/positions" \
    -H "Content-Type: application/json" \
    -d "{
      \"deliveryId\": \"DEL-SIM-001\",
      \"parcelId\": \"$PARCEL_ID\",
      \"latitude\": $LAT,
      \"longitude\": $LNG,
      \"speed\": 22.5,
      \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    }")

  HTTP_CODE=$(echo "$RESP" | tail -1)
  echo "Step $i/$STEPS — lat: $LAT, lng: $LNG — HTTP $HTTP_CODE"

  if [ "$i" -lt "$STEPS" ]; then
    sleep $INTERVAL
  fi
done

echo "---"
echo "Simulation terminée. Vérifier MailHog sur http://localhost:8025"
