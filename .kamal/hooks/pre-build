#!/usr/bin/env bash
set -euo pipefail

HOST_UID="${HOST_UID:-}"
HOST_GID="${HOST_GID:-}"
if [[ -z "$HOST_UID" || -z "$HOST_GID" ]]; then
  HOST_UID=$(stat -c '%u' . 2>/dev/null || echo "")
  HOST_GID=$(stat -c '%g' . 2>/dev/null || echo "")
fi

CERT_DIR="certs/mysql"

# Idempotency: if directory already exists, assume certs are in place and skip regeneration.
if [[ -d "$CERT_DIR" ]]; then
  echo "pre-build: $CERT_DIR already exists; skipping MySQL TLS cert generation."
  echo "pre-build: Remove the directory first if you need to regenerate." >&2
  exit 0
fi

mkdir -p "$CERT_DIR"

CA_KEY="$CERT_DIR/ca-key.pem"
CA_CRT="$CERT_DIR/ca.pem"
SERVER_KEY="$CERT_DIR/server-key.pem"
SERVER_CSR="$CERT_DIR/server.csr"
SERVER_CRT="$CERT_DIR/server-cert.pem"
OPENSSL_EXT="$CERT_DIR/server-ext.cnf"

DB_HOSTNAME="${DB_HOSTNAME:-veridian-db}"
ALT_NAMES="${ALT_NAMES:-DNS:${DB_HOSTNAME},DNS:localhost,IP:127.0.0.1}"

openssl genrsa -out "$CA_KEY" 4096
openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 3650 \
  -subj "/CN=Kamal MySQL CA" -out "$CA_CRT"

openssl genrsa -out "$SERVER_KEY" 4096

# SANs for server cert
cat > "$OPENSSL_EXT" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=${ALT_NAMES}
EOF

# CSR + sign
openssl req -new -key "$SERVER_KEY" -subj "/CN=${DB_HOSTNAME}" -out "$SERVER_CSR"
openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
  -out "$SERVER_CRT" -days 825 -sha256 -extfile "$OPENSSL_EXT"

# Compromise: MySQL in the container sees this file as “other”,
# so we keep the other-read bit but drop group read.
chmod 604 "$SERVER_KEY"
chmod 644 "$SERVER_CRT" "$CA_CRT"

if [[ $(id -u) -eq 0 && -n "$HOST_UID" && -n "$HOST_GID" ]]; then
  chown -R "$HOST_UID:$HOST_GID" "$CERT_DIR"
fi

echo "pre-build: Generated MySQL TLS certs in $CERT_DIR"
