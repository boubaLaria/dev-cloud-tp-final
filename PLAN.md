# Plan / Checklist finale — GreenLogistics TP Final

> Soutenance & livrables : **lundi 6 juillet 2026, 09h00**
> Stack LOCAL-FIRST : kind (3 nœuds) · ArgoCD · Redpanda · Vault · Linkerd · kube-prometheus-stack · Kubecost
> Formateur (accès lecture) : `abconsulting113@gmail.com`

---

## État des lieux (à jour)

| Composant | Manifests/Code | Sur le cluster local |
|---|---|---|
| CI GitHub Actions (build/test/Trivy/update-manifests) | ✅ complet | ✅ vert |
| ArgoCD App of Apps (`infra`, 4 services, `monitoring`) | ✅ complet | ✅ 6 apps **Synced/Healthy** |
| Terraform (ArgoCD, Prometheus, Vault, Loki, Redpanda, Rollouts, ESO, Linkerd) | ✅ complet | ✅ appliqué |
| kind-config.yaml (3 nœuds) | ✅ complet | ✅ cluster UP |
| Manifests k8s (deployments, services, HPA, rollout…) | ✅ complet | ✅ déployés |
| Prometheus recording rules (2 SLO + error budget) | ✅ complet + **bugs PromQL corrigés** | ✅ actives, alimentées |
| ServiceMonitors parcel-api / gps-ingestor | ✅ ajoutés | ✅ cibles `up` |
| NetworkPolicy `allow-metrics-scrape` | ✅ ajoutée | ✅ scrape OK |
| Dashboard Grafana custom SLO | ✅ ajouté | ✅ auto-importé (sidecar) |
| Alerte Alertmanager → MailHog | ✅ `AlertmanagerConfig` | ✅ email `[FIRING]` reçu |
| HPA (parcel-api, gps-ingestor) | ✅ complet | ✅ actifs |
| Vault + External Secrets | ✅ complet | ✅ secret provisionné, ESO `Ready` |
| Kubecost | ✅ complet | ✅ déployé |
| docs/architecture.md + ADR.md | ✅ complet | — |
| **RAPPORT_TECHNIQUE.md** | ✅ **rédigé** | — |
| **Slides soutenance** (`docs/soutenance.html` → PDF) | ✅ **généré** | — |
| **Captures d'écran** (`docs/captures/`) | ⏳ **à prendre** (guide prêt) | — |
| Nettoyage dépôt (34 artefacts Node/pyc morts) | ✅ **purgé** | — |
| Tag git `v1.0-soutenance` | ⏳ **à créer après commit** | — |

---

## Ce qu'il reste (actions humaines uniquement)

### 1. Commit + push (⚠️ à faire — rien n'est encore commité)
```bash
git add -A
git commit -m "fix(observability): Prometheus OOM + ServiceMonitors + dashboard SLO + alerte MailHog; docs: rapport + slides; chore: nettoyage artefacts morts"
git push
```
> Au push : la CI tourne (build/test/Trivy) **et** ArgoCD crée l'app `monitoring` + synce la NetworkPolicy depuis GitHub → les correctifs observabilité deviennent durables (GitOps).

### 2. Prendre les 5 captures → `docs/captures/`
Cluster déjà **tout vert** — voir le guide `docs/captures/README.md` (URLs + mots de passe).
1. `argocd-synced.png` — 6 apps Synced/Healthy
2. `grafana-slo.png` — dashboard « GreenLogistics — SLO parcel-api »
3. `ci-green.png` — pipeline GitHub Actions vert
4. `kubecost-namespaces.png` — coût par namespace
5. `mailhog-alert.png` — email d'alerte reçu

### 3. Exporter les slides en PDF
```bash
# Ouvrir docs/soutenance.html dans le navigateur → Cmd+P → « Enregistrer au format PDF »
open docs/soutenance.html
# → sauvegarder sous docs/soutenance.pdf
```

### 4. Tag git de la version soutenue (après commit + captures)
```bash
git tag v1.0-soutenance && git push --tags
```

### 5. Vérifier l'accès lecture du formateur
- Dépôt GitHub → Settings → Collaborators → `abconsulting113@gmail.com`

---

## Répétition des démos live (avant la soutenance)

> **Conseil** : enregistrer une vidéo de 60–90 s de chaque démo — plan B si le cluster crashe en live.

- [ ] **Self-Heal ArgoCD** (~90 s) : `kubectl scale deploy/parcel-api -n app --replicas=0` → resync auto
- [ ] **Canary Rollout** : `kubectl argo rollouts get rollout parcel-api -n app --watch`
- [ ] **HPA** : générer du trafic → `kubectl get hpa -n app -w`
- [ ] **Chaîne métier** : créer colis → `OUT_FOR_DELIVERY` → simulation GPS → email MailHog
- [ ] **Kubecost** : coût par namespace
- [ ] **Alerte SLO** : provoquer des 5xx → alerte `[FIRING]` dans MailHog

---

## Rappel — plan de la soutenance (25 min)

| Bloc | Durée | Contenu |
|---|---|---|
| Architecture | 5 min | 4 services, async Redpanda, GitOps, sécurité |
| Démo live | 10 min | chaîne métier + self-heal + HPA + observabilité + alerte |
| Retour d'expérience | 5 min | incidents (Prometheus OOM, ESO, migration Node→Python) |
| Q&A | 5 min | — |
