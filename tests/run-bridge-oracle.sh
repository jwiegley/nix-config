#!/usr/bin/env bash

set -euo pipefail

: "${BRIDGE_BIN:?}"
: "${BRIDGE_CLOSURE_PATHS:?}"
: "${BRIDGE_NODE_GUARD:?}"
: "${BRIDGE_ORACLE_PY:?}"
: "${PYTHON_BIN:?}"

oracle_base="$TMPDIR/task3-bridge-https-oracle"
certificate="$oracle_base/ca-and-server.pem"
private_key="$oracle_base/ca-and-server.key"
runtime_root="$oracle_base/runtime"

test ! -e "$oracle_base" && test ! -L "$oracle_base"
mkdir -p "$oracle_base"

openssl req \
	-x509 \
	-newkey rsa:2048 \
	-sha256 \
	-nodes \
	-days 1 \
	-subj /CN=task3-bridge-oracle \
	-addext 'basicConstraints=critical,CA:TRUE' \
	-addext 'keyUsage=critical,keyCertSign,digitalSignature,keyEncipherment' \
	-addext 'subjectAltName=IP:127.0.0.1,DNS:localhost' \
	-keyout "$private_key" \
	-out "$certificate" \
	>/dev/null 2>&1
chmod 0600 "$private_key"

PYTHONHASHSEED=0 "$PYTHON_BIN" "$BRIDGE_ORACLE_PY" \
	--bridge "$BRIDGE_BIN" \
	--guard "$BRIDGE_NODE_GUARD" \
	--certificate "$certificate" \
	--private-key "$private_key" \
	--runtime-root "$runtime_root" \
	--closure-paths "$BRIDGE_CLOSURE_PATHS"

test -s "$runtime_root/oracle-report.json"
