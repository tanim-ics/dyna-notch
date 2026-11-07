#!/bin/bash
# release-key.sh — create the update-signing key once (docs/SECURITY.md).
# The private key goes into your login Keychain (service com.tanim.dynanotch.release-signing) and never into the repo;
# the public key is printed for Sources/DynaNotchCore/Security.swift (UpdateTrust.releasePublicKey).
# Back the Keychain item up: without it, no future release can be signed and installed apps won't accept updates.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
SERVICE="com.tanim.dynanotch.release-signing"
if security find-generic-password -s "$SERVICE" -a ed25519 >/dev/null 2>&1; then
    echo "Key already in the Keychain. Public key:"
    security find-generic-password -s "$SERVICE" -a ed25519 -w | swift scripts/release-tools/release-key.swift public
    exit 0
fi
read -r PRIV PUB < <(swift scripts/release-tools/release-key.swift generate)
security add-generic-password -s "$SERVICE" -a ed25519 -l "DynaNotch release signing key" -w "$PRIV"
unset PRIV
echo "Private key stored in your login Keychain ($SERVICE)."
echo "Public key (put it in UpdateTrust.releasePublicKey):"
echo "$PUB"
