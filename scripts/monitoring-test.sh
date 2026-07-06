#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# monitoring-test.sh — teste la chaîne d'observabilité GreenLogistics de bout
# en bout : trafic → métriques Prometheus → alerte SLO → mail (MailHog).
#
# Chaîne testée :
#   parcel-api /metrics → ServiceMonitor → Prometheus (règle SLOErrorRateBreach
#   si 5xx > 1% pendant 2 min) → Alertmanager (team=greenlogistics) → MailHog.
#
# Injection de panne : on coupe PostgreSQL (scale StatefulSet → 0). Comme l'app
# ArgoCD `infra` a le self-heal actif, on suspend son auto-sync pendant la panne
# et on le réactive à la réparation.
#
# Usage : bash scripts/monitoring-test.sh {load|break|errors|alerts|mail|heal|status|demo}
# (ou via les cibles `make mon-*`).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CTX="kind-greenlogistics"
KUBECTL="kubectl --context $CTX"
NS="app"
INFRA_APP="infra"          # application ArgoCD qui gère PostgreSQL

# Ports locaux DÉDIÉS au script (≠ des cibles make grafana/prometheus/… pour
# pouvoir tourner en parallèle sans "address already in use").
API_PORT=13000
PROM_PORT=19090
ALERT_PORT=19093
MAIL_PORT=18025

PF_PIDS=()
PF_DONE=""
AUTO_HEAL=0   # mis à 1 par `demo` : répare PostgreSQL même si interrompu

# ── couleurs ────────────────────────────────────────────────────────────────
c_blue()   { printf '\033[36m%s\033[0m\n' "$*"; }
c_green()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_red()    { printf '\033[31m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

# ── nettoyage : ferme les tunnels, répare si nécessaire ──────────────────────
cleanup() {
  set +e; set +u
  for pid in "${PF_PIDS[@]}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
  if [ "$AUTO_HEAL" = "1" ]; then
    c_yellow "↩︎  Interruption détectée — réparation de PostgreSQL…"
    _heal
  fi
}
trap cleanup EXIT INT TERM

# ── port-forward paresseux (une seule fois par port) ─────────────────────────
pf() {  # pf <ns> <svc> <local> <remote>
  local ns=$1 svc=$2 lport=$3 rport=$4
  case " $PF_DONE " in *" $lport "*) return 0 ;; esac
  $KUBECTL port-forward -n "$ns" "svc/$svc" "$lport:$rport" >/dev/null 2>&1 &
  local pid=$!
  PF_PIDS+=("$pid")
  local i
  for i in $(seq 1 40); do
    if curl -s -o /dev/null "http://localhost:$lport" 2>/dev/null; then
      PF_DONE="$PF_DONE $lport"; return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      c_red "❌ port-forward $svc:$rport a échoué"; return 1
    fi
    sleep 0.3
  done
  PF_DONE="$PF_DONE $lport"; return 0
}

urlencode() { jq -sRr @uri <<<"$1"; }

# valeur scalaire d'une requête PromQL (premier résultat) ou "n/a"
promq() {
  local q; q=$(urlencode "$1")
  curl -s "http://localhost:$PROM_PORT/api/v1/query?query=$q" \
    | jq -r '.data.result[0].value[1] // "n/a"'
}

# formate un ratio [0..1] en pourcentage
pct() {
  case "${1:-}" in
    ''|n/a) echo "n/a" ;;
    *) awk "BEGIN{printf \"%.2f%%\", ${1}*100}" 2>/dev/null || echo "$1" ;;
  esac
}

# ── trafic HTTP vers parcel-api (via port-forward direct, sans Ingress) ──────
_traffic() {  # _traffic <count>
  local n=${1:-100} i ok=0 err=0 code
  for i in $(seq 1 "$n"); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$API_PORT/parcels" || echo 000)
    case "$code" in 2*) ok=$((ok+1)) ;; *) err=$((err+1)) ;; esac
    if [ $((i % 5)) -eq 0 ]; then
      curl -s -o /dev/null -X POST "http://localhost:$API_PORT/parcels" \
        -H 'Content-Type: application/json' \
        -d '{"senderName":"Load","recipientName":"Test","recipientEmail":"load@example.com","recipientAddress":"1 rue de Test, Paris","recipientLat":48.85,"recipientLng":2.35}' 2>/dev/null || true
    fi
  done
  printf '   → %s requêtes (%s OK / %s erreurs)\n' "$n" "$ok" "$err"
}

# ── répare PostgreSQL + réactive l'auto-sync ArgoCD (idempotent, silencieux) ─
_heal() {
  $KUBECTL -n "$NS" scale statefulset/postgres --replicas=1 >/dev/null 2>&1 || true
  $KUBECTL -n "$NS" rollout status statefulset/postgres --timeout=120s >/dev/null 2>&1 || true
  $KUBECTL -n argocd patch application "$INFRA_APP" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' >/dev/null 2>&1 || true
}

# ─────────────────────────────── commandes ──────────────────────────────────

cmd_load() {
  local secs=${1:-30}
  c_blue "▶ Trafic sain pendant ${secs}s (baseline SLO)…"
  pf "$NS" parcel-api "$API_PORT" 3000
  local end=$((SECONDS + secs)) total=0
  while [ "$SECONDS" -lt "$end" ]; do
    curl -s -o /dev/null "http://localhost:$API_PORT/parcels" 2>/dev/null || true
    total=$((total + 1))
  done
  c_green "✅ Baseline terminée (${total} requêtes saines)."
}

cmd_break() {
  local n=${1:-150}
  c_yellow "▶ Suspension de l'auto-sync ArgoCD ($INFRA_APP) pour empêcher le self-heal…"
  $KUBECTL -n argocd patch application "$INFRA_APP" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null
  c_yellow "▶ Arrêt de PostgreSQL (statefulset/postgres → 0 réplica)…"
  $KUBECTL -n "$NS" scale statefulset/postgres --replicas=0 >/dev/null
  $KUBECTL -n "$NS" wait --for=delete pod -l app=postgres --timeout=60s >/dev/null 2>&1 || true
  c_red "▶ Envoi de $n requêtes vers parcel-api (échecs 5xx attendus)…"
  pf "$NS" parcel-api "$API_PORT" 3000
  _traffic "$n"
  c_yellow "⚠️  PostgreSQL est ARRÊTÉ — l'alerte SLOErrorRateBreach se déclenchera après ~2 min."
  c_yellow "    Vérifier :  make mon-alerts   puis   make mon-mail"
  c_yellow "    Réparer  :  make mon-heal"
}

cmd_heal() {
  c_blue "▶ Réparation : redémarrage de PostgreSQL + réactivation de l'auto-sync ArgoCD…"
  _heal
  c_green "✅ PostgreSQL rétabli, auto-sync ArgoCD réactivé. L'alerte se résoudra sous peu (→ mail de résolution)."
}

cmd_errors() {
  c_blue "▶ Métriques SLO (Prometheus)…"
  pf monitoring kps-kube-prometheus-stack-prometheus "$PROM_PORT" 9090
  local rate budget p95 alert
  rate=$(promq 'slo:parcel_api:error_rate:ratio5m')
  budget=$(promq 'slo:parcel_api:error_budget_remaining')
  p95=$(promq 'slo:parcel_api:latency_p95:5m')
  alert=$(curl -s "http://localhost:$PROM_PORT/api/v1/query?query=$(urlencode 'ALERTS{alertname="SLOErrorRateBreach"}')" \
    | jq -r '.data.result[0].metric.alertstate // "inactive"')
  printf '   Taux d'\''erreur 5xx        : %s\n' "$(pct "$rate")"
  printf '   Error budget restant      : %s\n' "$(pct "$budget")"
  printf '   Latence P95               : %s s\n' "$p95"
  printf '   Alerte SLOErrorRateBreach : %s\n' "$alert"
}

cmd_alerts() {
  c_blue "▶ Alertes actives (Alertmanager)…"
  pf monitoring kps-kube-prometheus-stack-alertmanager "$ALERT_PORT" 9093
  local out
  out=$(curl -s "http://localhost:$ALERT_PORT/api/v2/alerts" \
    | jq -r '.[] | select(.labels.team=="greenlogistics") | "   • \(.labels.alertname) [\(.labels.severity // "?")] → \(.status.state)"')
  if [ -z "$out" ]; then
    c_yellow "   (aucune alerte GreenLogistics active pour l'instant)"
  else
    echo "$out"
  fi
}

cmd_mail() {
  c_blue "▶ Mails d'alerte reçus (MailHog)…"
  pf mail mailhog "$MAIL_PORT" 8025
  local total
  total=$(curl -s "http://localhost:$MAIL_PORT/api/v2/messages" | jq -r '.total // 0')
  printf '   %s mail(s) dans la boîte oncall@greenlogistics.local\n' "$total"
  curl -s "http://localhost:$MAIL_PORT/api/v2/messages" \
    | jq -r '.items[]? | "   ✉️  \(.Content.Headers.Subject[0] // "(sans objet)")  →  \(.Content.Headers.To[0] // "?")"' \
    | head -10
}

cmd_status() {
  c_blue "════════ État du monitoring GreenLogistics ════════"
  pf monitoring kps-kube-prometheus-stack-prometheus "$PROM_PORT" 9090
  local up
  up=$(promq 'count(up{job=~"parcel-api|gps-ingestor"}==1)')
  printf 'Cibles applicatives scrapées (UP) : %s\n' "$up"
  echo
  cmd_errors
  echo
  cmd_alerts
  echo
  cmd_mail
}

cmd_demo() {
  local wait_s=${1:-160}
  AUTO_HEAL=1
  c_blue "══════════ DÉMO OBSERVABILITÉ END-TO-END ══════════"
  c_blue "1/6 · Baseline de trafic sain (20 s)"
  cmd_load 20
  echo
  c_blue "2/6 · Injection de panne PostgreSQL + trafic d'erreur"
  cmd_break 150
  echo
  c_blue "3/6 · Attente ${wait_s}s (alerte for:2m + groupWait Alertmanager), trafic d'erreur maintenu…"
  local r
  for r in $(seq "$wait_s" -10 1); do
    printf '\r   ⏳ %3ss restantes  ' "$r"
    _traffic 5 >/dev/null 2>&1 || true
    sleep 10
  done
  printf '\r%40s\r' ''
  echo
  c_blue "4/6 · Taux d'erreur & état de l'alerte"
  cmd_errors
  echo
  c_blue "5/6 · Alertes Alertmanager"
  cmd_alerts
  echo
  c_blue "      · Mails reçus (MailHog)"
  cmd_mail
  echo
  c_blue "6/6 · Réparation"
  cmd_heal
  AUTO_HEAL=0
  c_green "✅ Démo terminée — chaîne trafic → métrique → alerte → mail vérifiée."
}

# ─────────────────────────────── dispatch ───────────────────────────────────
case "${1:-}" in
  load)   shift; cmd_load   "${1:-30}"  ;;
  break)  shift; cmd_break  "${1:-150}" ;;
  errors) cmd_errors ;;
  alerts) cmd_alerts ;;
  mail)   cmd_mail ;;
  heal)   cmd_heal ;;
  status) cmd_status ;;
  demo)   shift; cmd_demo   "${1:-160}" ;;
  *)
    echo "Usage: $0 {load|break|errors|alerts|mail|heal|status|demo}"
    echo "  load [secs]   trafic sain (baseline)"
    echo "  break [n]     coupe PostgreSQL + envoie n requêtes → 5xx"
    echo "  errors        taux d'erreur SLO + état alerte (Prometheus)"
    echo "  alerts        alertes actives (Alertmanager)"
    echo "  mail          mails d'alerte reçus (MailHog)"
    echo "  heal          répare PostgreSQL + réactive l'auto-sync ArgoCD"
    echo "  status        vue d'ensemble"
    echo "  demo [secs]   scénario complet baseline→panne→alerte→mail→réparation"
    exit 1
    ;;
esac
