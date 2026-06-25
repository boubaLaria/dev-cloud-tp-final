# Architecture Decision Records — GreenLogistics

---

## ADR-001 — Choix du message broker : Redpanda

**Date** : 2026-06-25  
**Statut** : Accepté

### Contexte
Le service gps-ingestor doit publier des positions GPS à haute fréquence (1/5s par livreur) vers le notifier de manière asynchrone et résiliente. Trois options ont été évaluées : RabbitMQ, NATS JetStream, Redpanda.

### Décision
Utiliser **Redpanda** (compatible Kafka).

### Conséquences
- **Positif** : API Kafka standard (KafkaJS compatible sans modification), bonne documentation, Dead Letter Queue native, monitoring Prometheus intégré.
- **Positif** : Redpanda est plus léger que Kafka (pas de ZooKeeper/KRaft séparé).
- **Négatif** : Chart Helm plus gourmand (~400Mo RAM) que NATS (~50Mo). Acceptable sur un cluster 16Go.
- **Alternative écartée** : RabbitMQ — protocole AMQP différent, nécessite une autre librairie client. NATS — moins répandu en production, tooling moins mature.

---

## ADR-002 — Choix de la base de données : PostgreSQL StatefulSet

**Date** : 2026-06-25  
**Statut** : Accepté

### Contexte
parcel-api nécessite une persistance relationnelle pour les colis et les événements de livraison. Options : PostgreSQL, MongoDB, SQLite.

### Décision
Utiliser **PostgreSQL 16 en StatefulSet Kubernetes** avec PersistentVolumeClaim.

### Conséquences
- **Positif** : Schéma relationnel adapté aux données structurées (colis, statuts, événements). Support UUID natif via pgcrypto.
- **Positif** : Compatible avec les ORM Node.js (pg, Prisma, Sequelize).
- **Négatif** : StatefulSet plus complexe qu'un Deployment (volumes persistants, headless service).
- **Alternative écartée** : MongoDB — schéma flexible non nécessaire ici, données structurées. SQLite — pas adapté à un environnement multi-replicas.

---

## ADR-003 — Service mesh : Linkerd plutôt qu'Istio

**Date** : 2026-06-25  
**Statut** : Accepté

### Contexte
Le sujet requiert mTLS automatique intra-cluster pour satisfaire les exigences de sécurité (bloc 4.7). Deux options : Linkerd, Istio.

### Décision
Utiliser **Linkerd** (version stable 2.x).

### Conséquences
- **Positif** : Consommation RAM ~400Mo vs ~1Go+ pour Istio. Critique sur une machine 16Go avec toute la stack.
- **Positif** : Installation simple (linkerd install | kubectl apply), mTLS activé par namespace annotation.
- **Positif** : Dashboard Linkerd Viz intégré pour la démo.
- **Négatif** : Moins de fonctionnalités avancées qu'Istio (pas de traffic mirroring, rate limiting limité).
- **Alternative écartée** : Istio — trop lourd pour notre contrainte RAM locale.

---

## ADR-004 — Pattern CI/CD : pull-based via ArgoCD

**Date** : 2026-06-25  
**Statut** : Accepté

### Contexte
En stack locale, la CI (GitHub Actions) n'a pas accès direct au cluster kind. Deux patterns pour déployer : push-based (CI pousse sur le cluster), pull-based (ArgoCD tire depuis un repo gitops).

### Décision
Utiliser le **pattern pull-based** : la CI pousse l'image sur GHCR + met à jour le tag dans `greenlogistics-gitops`. ArgoCD dans le cluster tire les changements.

### Conséquences
- **Positif** : Élimine le problème d'authentification CI → cluster local (pas de kubeconfig exposé dans GitHub Actions).
- **Positif** : Aligné avec les bonnes pratiques GitOps (git comme source de vérité).
- **Positif** : Self-Heal fonctionne nativement : ArgoCD re-synchronise si quelqu'un modifie le cluster manuellement.
- **Négatif** : Latence de déploiement légèrement plus longue (ArgoCD poll toutes les 3 minutes par défaut).
- **Alternative écartée** : webhook ArgoCD depuis CI — complexité d'exposition du serveur ArgoCD vers internet en local.

---

## ADR-005 — Secrets : HashiCorp Vault + External Secrets Operator

**Date** : 2026-06-25  
**Statut** : Accepté

### Contexte
La DATABASE_URL contient un mot de passe. Elle ne doit pas être committée dans git ni dans les manifestes K8s en clair.

### Décision
Utiliser **Vault dev-mode** comme source de secrets, synchronisé vers des K8s Secrets via **External Secrets Operator**.

### Conséquences
- **Positif** : Aucun secret dans le dépôt git. Rotation possible sans redéploiement.
- **Positif** : Pattern identique à ce qui serait fait en production avec Vault Enterprise ou AWS Secrets Manager.
- **Négatif** : Vault dev-mode resets à chaque redémarrage du pod — nécessite de re-provisionner les secrets après un crash. Acceptable en environnement de dev/démo.
- **Alternative écartée** : Sealed Secrets (Bitnami) — ne permet pas la rotation dynamique. Kubernetes Secrets en clair — interdit par les exigences de sécurité.
