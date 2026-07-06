# GreenLogistics — commandes de test & démo
# Usage : `make` ou `make help` pour la liste.

CLUSTER       := greenlogistics
CTX           := kind-greenlogistics
NS            := app
HOST          := greenlogistics.local
# L'Ingress est exposé par kind sur le port hôte 8080 (containerPort 80 → hostPort 8080).
BASE          := http://$(HOST):8080
PY_SERVICES   := parcel-api gps-ingestor
NODE_SERVICES := notifier tracker-front
KUBECTL       := kubectl --context $(CTX)
SIMULATE      := services/gps-ingestor/scripts/simulate.sh

.DEFAULT_GOAL := help
.PHONY: help test test-py test-node lint lint-py lint-node \
        cluster-up cluster-down status wait \
        smoke seed seed-clean simulate demo \
        grafana prometheus alertmanager vault loki argocd-ui mailhog logs \
        mon-load mon-break mon-errors mon-alerts mon-mail mon-heal mon-status mon-demo

## ─────────────────────────── Aide ───────────────────────────
help: ## Affiche cette aide
	@echo "GreenLogistics — cibles disponibles :"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}'

## ─────────────── Tests locaux (sans cluster) ────────────────
test: test-py test-node ## Lance tous les tests unitaires (Python + Node)

test-py: ## Tests Python (parcel-api, gps-ingestor)
	@for svc in $(PY_SERVICES); do \
	  echo "▶ pytest — $$svc"; \
	  ( cd services/$$svc && pip install -q -r requirements-dev.txt && pytest --tb=short -q ) || exit 1; \
	done

test-node: ## Tests Node (notifier, tracker-front)
	@for svc in $(NODE_SERVICES); do \
	  echo "▶ npm test — $$svc"; \
	  ( cd services/$$svc && npm ci --silent && npm test ) || exit 1; \
	done

lint: lint-py lint-node ## Lint tous les services

lint-py: ## ruff sur les services Python
	@for svc in $(PY_SERVICES); do \
	  echo "▶ ruff — $$svc"; \
	  ( cd services/$$svc && ruff check src/ tests/ ) || exit 1; \
	done

lint-node: ## eslint sur les services Node
	@for svc in $(NODE_SERVICES); do \
	  echo "▶ eslint — $$svc"; \
	  ( cd services/$$svc && npm run lint ) || exit 1; \
	done

## ──────────────────── Cluster (kind) ────────────────────────
cluster-up: ## Crée le cluster kind s'il n'existe pas
	@kind get clusters | grep -qx $(CLUSTER) \
	  && echo "✅ cluster '$(CLUSTER)' déjà présent" \
	  || kind create cluster --config kind-config.yaml

cluster-down: ## Supprime le cluster kind
	kind delete cluster --name $(CLUSTER)

status: ## État des pods app + applications ArgoCD
	@echo "── Pods namespace $(NS) ──"
	@$(KUBECTL) get pods -n $(NS)
	@echo "── Applications ArgoCD ──"
	@$(KUBECTL) get applications -n argocd 2>/dev/null || echo "(argocd indisponible)"

wait: ## Attend que les pods du namespace app soient prêts
	$(KUBECTL) wait --for=condition=ready pod --all -n $(NS) --timeout=180s

## ──────────────── Tests e2e / démo (cluster) ────────────────
smoke: ## Smoke test e2e via l'Ingress (front + CRUD colis)
	@echo "▶ Front ($(BASE)/)";            curl -fsS -o /dev/null -w "  HTTP %{http_code}\n" $(BASE)/
	@echo "▶ Liste colis ($(BASE)/api/parcels)"; curl -fsS $(BASE)/api/parcels | head -c 300; echo
	@echo "▶ Création d'un colis de test"; \
	  code=$$(curl -fsS -X POST $(BASE)/api/parcels -H 'Content-Type: application/json' \
	    -d '{"senderName":"Smoke","recipientName":"Test","recipientEmail":"smoke@example.com","recipientAddress":"1 rue de Test, Paris","recipientLat":48.8566,"recipientLng":2.3522}' \
	    | jq -r '.tracking_code'); \
	  echo "  ✅ colis créé : $$code"
	@echo "✅ smoke OK"

seed: ## Déploie et exécute le Job de seed (données de démo)
	$(KUBECTL) apply -f k8s/seed/seed-job.yaml
	$(KUBECTL) wait --for=condition=complete job/demo-seed -n $(NS) --timeout=180s || true
	$(KUBECTL) logs -n $(NS) job/demo-seed

seed-clean: ## Supprime le Job de seed (pour le relancer)
	$(KUBECTL) delete job demo-seed -n $(NS) --ignore-not-found

simulate: ## Simule un trajet GPS — usage : make simulate PARCEL=<id>
	@test -n "$(PARCEL)" || { echo "Usage: make simulate PARCEL=<parcelId>"; exit 1; }
	bash $(SIMULATE) $(PARCEL)

demo: ## Démo complète : crée un colis OUT_FOR_DELIVERY + trajet GPS
	@id=$$(curl -fsS -X POST $(BASE)/api/parcels -H 'Content-Type: application/json' \
	    -d '{"senderName":"Alice","recipientName":"Bob","recipientEmail":"bob@example.com","recipientAddress":"12 rue de la Paix, Paris","recipientLat":48.8698,"recipientLng":2.3322}' \
	    | jq -r '.id'); \
	  echo "📦 colis $$id"; \
	  curl -fsS -X PATCH $(BASE)/api/parcels/$$id/status -H 'Content-Type: application/json' \
	    -d '{"status":"OUT_FOR_DELIVERY"}' >/dev/null; \
	  echo "🚚 statut → OUT_FOR_DELIVERY"; \
	  bash $(SIMULATE) $$id

## ──────────────────── Accès aux UIs ─────────────────────────
grafana: ## Port-forward Grafana → http://localhost:9090 (admin/prom-operator)
	$(KUBECTL) port-forward -n monitoring svc/kps-grafana 9090:80

prometheus: ## Port-forward Prometheus → http://localhost:9091
	$(KUBECTL) port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9091:9090

alertmanager: ## Port-forward Alertmanager → http://localhost:9093
	$(KUBECTL) port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9093

vault: ## Port-forward Vault → http://localhost:8200 (token: root)
	$(KUBECTL) port-forward -n vault svc/vault 8200:8200

loki: ## Port-forward Loki → http://localhost:3100 (API ; à consulter via Grafana)
	$(KUBECTL) port-forward -n monitoring svc/loki 3100:3100

argocd-ui: ## Port-forward ArgoCD → https://localhost:8080
	$(KUBECTL) port-forward -n argocd svc/argocd-server 8080:443

mailhog: ## Port-forward MailHog → http://localhost:8025
	$(KUBECTL) port-forward -n mail svc/mailhog 8025:8025

logs: ## Logs d'un service — usage : make logs SVC=parcel-api
	@test -n "$(SVC)" || { echo "Usage: make logs SVC=<service>"; exit 1; }
	$(KUBECTL) logs -n $(NS) -l app=$(SVC) --tail=100 -f

## ────────────── Test observabilité / alerting ───────────────
MON := bash scripts/monitoring-test.sh

mon-load: ## Trafic sain (baseline SLO) — usage : make mon-load [SECS=30]
	$(MON) load $(SECS)

mon-break: ## Coupe PostgreSQL + envoie du trafic → 5xx — usage : make mon-break [REQ=150]
	$(MON) break $(REQ)

mon-errors: ## Taux d'erreur SLO + état de l'alerte (Prometheus)
	$(MON) errors

mon-alerts: ## Alertes actives (Alertmanager)
	$(MON) alerts

mon-mail: ## Mails d'alerte reçus (MailHog)
	$(MON) mail

mon-heal: ## Répare PostgreSQL + réactive l'auto-sync ArgoCD
	$(MON) heal

mon-status: ## Vue d'ensemble monitoring (targets, SLO, alertes, mails)
	$(MON) status

mon-demo: ## Scénario complet : baseline → panne → alerte → mail → réparation
	$(MON) demo $(SECS)
