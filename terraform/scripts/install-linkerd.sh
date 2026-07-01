#!/usr/bin/env bash
set -euo pipefail

KUBE_CONTEXT="kind-greenlogistics"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "==> Génération des certificats Linkerd..."

# Config CA (trust anchor)
cat > "$TMPDIR/ca.cnf" <<'EOF'
[req]
distinguished_name = req_dn
x509_extensions    = v3_ca
prompt             = no
[req_dn]
CN = root.linkerd.cluster.local
[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage         = critical,digitalSignature,keyCertSign,cRLSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

# Config issuer (intermediate CA)
cat > "$TMPDIR/issuer.cnf" <<'EOF'
[req]
distinguished_name = req_dn
req_extensions     = v3_req
prompt             = no
[req_dn]
CN = identity.linkerd.cluster.local
[v3_req]
basicConstraints = critical,CA:TRUE
keyUsage         = critical,digitalSignature,keyCertSign,cRLSign
EOF

cat > "$TMPDIR/issuer_ext.cnf" <<'EOF'
basicConstraints = critical,CA:TRUE
keyUsage         = critical,digitalSignature,keyCertSign,cRLSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

# Trust anchor
openssl ecparam -name prime256v1 -genkey -noout -out "$TMPDIR/ca.key"
openssl req -x509 -key "$TMPDIR/ca.key" -days 365 \
  -out "$TMPDIR/ca.crt" -config "$TMPDIR/ca.cnf"

# Issuer
openssl ecparam -name prime256v1 -genkey -noout -out "$TMPDIR/issuer.key"
openssl req -new -key "$TMPDIR/issuer.key" -out "$TMPDIR/issuer.csr" \
  -config "$TMPDIR/issuer.cnf"
openssl x509 -req -in "$TMPDIR/issuer.csr" \
  -CA "$TMPDIR/ca.crt" -CAkey "$TMPDIR/ca.key" -CAcreateserial \
  -days 365 -out "$TMPDIR/issuer.crt" \
  -extfile "$TMPDIR/issuer_ext.cnf"

echo "==> Ajout du repo Helm Linkerd..."
helm repo add linkerd https://helm.linkerd.io/stable 2>/dev/null || true
helm repo update linkerd

echo "==> Installation des CRDs Linkerd..."
helm upgrade --install linkerd-crds linkerd/linkerd-crds \
  --kube-context "$KUBE_CONTEXT" \
  -n linkerd --create-namespace \
  --wait --timeout 5m

echo "==> Installation du control plane Linkerd..."
helm upgrade --install linkerd-control-plane linkerd/linkerd-control-plane \
  --kube-context "$KUBE_CONTEXT" \
  -n linkerd \
  --set-file identityTrustAnchorsPEM="$TMPDIR/ca.crt" \
  --set-file identity.issuer.tls.crtPEM="$TMPDIR/issuer.crt" \
  --set-file identity.issuer.tls.keyPEM="$TMPDIR/issuer.key" \
  --wait --timeout 5m

echo "==> Linkerd installé avec succès."
