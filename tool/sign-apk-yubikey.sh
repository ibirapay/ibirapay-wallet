#!/usr/bin/env bash
# Signs a release APK with the wallet's release key, which lives in the YubiKey (PIV slot 9A, ECCP256).
# Interactive on purpose: it asks for the PIV PIN and you touch the key. Run it in your own terminal.
#   tool/sign-apk-yubikey.sh dist/<name>.apk.unsigned.apk      -> dist/<name>.apk (signed, verified)
# Needs: the ykcs11 package (libykcs11), the key + certificate in slot 9A.
# The PIN is read without echo and goes to apksigner on stdin, never on a command line.
set -euo pipefail
cd "$(dirname "$0")/.."
in=${1:?usage: tool/sign-apk-yubikey.sh <unsigned.apk>}
[[ $in == *.unsigned.apk && -f $in ]] || { echo "sign-apk: expected an existing dist/*.unsigned.apk" >&2; exit 1; }
export ANDROID_HOME=${ANDROID_HOME:-$HOME/opt/mobile/android-sdk}
export JAVA_HOME=${JAVA_HOME:-$HOME/opt/mobile/jdk}
export PATH="$JAVA_HOME/bin:$PATH"
APKSIGNER=$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)
# (a glob that matches nothing makes ls exit 2, and with pipefail that would kill the script silently: hence the || true)
LIB=${YKCS11:-$( { ls /usr/lib/x86_64-linux-gnu/libykcs11.so* /usr/lib/libykcs11.so* 2>/dev/null || true; } | head -1)}
[[ -n $LIB ]] || { echo "sign-apk: libykcs11 not found (sudo apt install ykcs11, or set YKCS11=/path/libykcs11.so)" >&2; exit 1; }
cfg=$(mktemp); trap 'rm -f "$cfg"' EXIT
printf 'name = ykcs11\nlibrary = %s\n' "$LIB" > "$cfg"
ksargs=(--ks NONE --ks-type PKCS11 --provider-class sun.security.pkcs11.SunPKCS11 --provider-arg "$cfg")

read -rsp "YubiKey PIV PIN: " PIN; echo
# The certificate in slot 9A is the one labelled for PIV Authentication; list the aliases instead of guessing.
alias=$( { printf '%s\n' "$PIN" | keytool -list -keystore NONE -storetype PKCS11 -providerClass sun.security.pkcs11.SunPKCS11 -providerArg "$cfg" 2>/dev/null \
  | sed -n 's/^\([^,]*Authentication[^,]*\), .*PrivateKeyEntry.*/\1/p' | head -1; } || true)
[[ -n $alias ]] || { echo "sign-apk: no key with a PIV Authentication certificate found: is slot 9A set up?" >&2; exit 1; }
echo "signing with key: $alias   (touch the YubiKey when it blinks)"
out=${in%.unsigned.apk}
# apksigner builds the PKCS#11 provider by reflection; the JDK hides sun.security.pkcs11 unless it is exported. (Its -J option
# cannot carry a double-dash JDK flag, so the JVM reads it from JAVA_TOOL_OPTIONS, for this one command only.)
printf '%s\n' "$PIN" | JAVA_TOOL_OPTIONS="--add-exports=jdk.crypto.cryptoki/sun.security.pkcs11=ALL-UNNAMED" "$APKSIGNER" sign "${ksargs[@]}" --ks-key-alias "$alias" --ks-pass stdin --out "$out" "$in"
unset PIN

"$APKSIGNER" verify --verbose --print-certs "$out" | sed -n '1,8p'
fp=$("$APKSIGNER" verify --print-certs "$out" | sed -n 's/.*certificate SHA-256 digest: //p' | head -1)
pin=tool/release-cert.sha256
if [[ -f $pin ]]; then
  [[ $fp == "$(tr -d '[:space:]' < "$pin")" ]] || { echo "sign-apk: SIGNER CERT DOES NOT MATCH $pin: do NOT publish $out" >&2; rm -f "$out"; exit 1; }
  echo "signer matches the pinned release certificate ($pin)"
else
  echo "FIRST SIGNING: record this certificate fingerprint in $pin and commit it, so a wrong key can never sign a release:"
  echo "$fp"
fi
echo "$out"
