#!/usr/bin/env bash
# Point cangjie/harmony/build-profile.json5 at a debug signing material set for THIS bundle.
#
# Why this exists: hvigor signs with whatever the `default` product's `signingConfigs` names, and a
# duplicate profile is rejected with
#   00303074 Configuration Error / The bundleName in app.json5 does not match the bundleName in the
#   generated SigningConfigs
# A HarmonyOS device only accepts a debug HAP whose provisioning profile (.p7b) was issued by AGC for
# this exact bundleName and lists the device's UDID, so the material has to be produced outside this
# repository (DevEco Studio, devecocli, or AGC) and then plugged in here.
#
# Everything is a parameter on purpose — no paths are baked in, so the same command works on another
# machine, with a different keystore directory, or with material AGC emitted under another name.
#
# Usage:
#   cangjie/scripts/harmony/set_signing_material.sh \
#     --store-file   <keystore.p12>            # keystore holding the signing key pair
#     --key-alias    <alias>                   # key alias inside the keystore
#     --cert         <certificate.cer>         # signing certificate (PEM/DER)
#     --profile      <profile.p7b>             # AGC debug profile for this bundleName + device UDID
#    [--store-password <value>]                # DevEco-encrypted hex, or plain; omit to keep the current one
#    [--key-password   <value>]                # a plain password is encrypted here (see below)
#    [--sign-alg       SHA256withECDSA]
#    [--product        default]
#    [--devsign-material <dir>]                # work-key material (default ~/.ohos/config/material)
#    [--dry-run]                               # validate and print, do not touch build-profile.json5
#
# What it checks before writing (a bad profile is otherwise only reported by a long hvigor run):
#   * every input file exists and is non-empty
#   * the profile's bundle-name equals AppScope/app.json5's bundleName
#   * the profile's authorized device UDIDs (install fails for any other device)
#   * the keystore password form hvigor accepts (see the password note below)
#
# Passwords: hvigor does not accept a plaintext keystore password. It rejects anything shorter than
# 32 characters with 00303116 and expects DevEco's ciphertext, which it decrypts with a work key
# derived from the *machine-local* material directory <dirname(storeFile)>/material
# (DevEco keeps that directory in ~/.ohos/config/material; devsign_password.py reimplements the
# scheme from hvigor-ohos-plugin/src/utils/decipher-util.js). So:
#   * a DevEco ciphertext is passed through unchanged;
#   * a plaintext password is encrypted here, and `material` is symlinked next to the keystore;
#   * the result only decrypts on THIS machine — which is why a ciphertext may be committed while a
#     plaintext password may not.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

STORE_FILE=""
KEY_ALIAS=""
CERT=""
PROFILE=""
STORE_PASSWORD=""
KEY_PASSWORD=""
SIGN_ALG="SHA256withECDSA"
PRODUCT="default"
DEVSIGN_MATERIAL="${DEVSIGN_MATERIAL:-$HOME/.ohos/config/material}"
DRY_RUN=0

usage() {
  sed -n '2,42p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

CIPHER="$SCRIPT_DIR/devsign_password.py"

# True when $1 already is a password hvigor can decrypt with $DEVSIGN_MATERIAL: hex, even length,
# at least 32 characters, and the work key actually opens it. A 32+ character plaintext password is
# therefore still recognised as plaintext when decryption fails, which is why this tries rather than
# pattern-matches.
is_devsign_cipher() {
  local value="$1"
  [ "${#value}" -ge 32 ] || return 1
  [ $(( ${#value} % 2 )) -eq 0 ] || return 1
  case "$value" in *[!0-9a-fA-F]*) return 1 ;; esac
  python3 "$CIPHER" decrypt "$DEVSIGN_MATERIAL" "$value" >/dev/null 2>&1
}

encrypt_password() {
  printf '%s' "$1" | python3 "$CIPHER" encrypt "$DEVSIGN_MATERIAL"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --store-file)     STORE_FILE="${2:-}"; shift 2 ;;
    --key-alias)      KEY_ALIAS="${2:-}"; shift 2 ;;
    --cert)           CERT="${2:-}"; shift 2 ;;
    --profile)        PROFILE="${2:-}"; shift 2 ;;
    --store-password) STORE_PASSWORD="${2:-}"; shift 2 ;;
    --key-password)   KEY_PASSWORD="${2:-}"; shift 2 ;;
    --sign-alg)       SIGN_ALG="${2:-}"; shift 2 ;;
    --product)        PRODUCT="${2:-}"; shift 2 ;;
    --devsign-material) DEVSIGN_MATERIAL="${2:-}"; shift 2 ;;
    --dry-run)        DRY_RUN=1; shift ;;
    -h|--help)        usage 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ -n "$STORE_FILE" ] && [ -n "$KEY_ALIAS" ] && [ -n "$CERT" ] && [ -n "$PROFILE" ] || {
  warn "missing required argument(s)"
  usage 1
}

for f in "$STORE_FILE" "$CERT" "$PROFILE"; do
  require_file "$f" "signing material"
  [ -s "$f" ] || die "$f is empty"
done

BUILD_PROFILE="$CJ_ROOT/harmony/build-profile.json5"
require_file "$BUILD_PROFILE" "harmony project"

BUNDLE="$(app_bundle_name)"
[ -n "$BUNDLE" ] || die "cannot read bundleName from cangjie/harmony/AppScope/app.json5"

PROFILE_BUNDLE="$(profile_bundle_name "$PROFILE" || true)"
DEVICE_IDS="$(profile_device_ids "$PROFILE" || true)"

log "bundleName       : $BUNDLE"
log "profile bundle-name: ${PROFILE_BUNDLE:-<unreadable>}"
log "profile device-ids : ${DEVICE_IDS:-<none listed — a release profile, or an unreadable payload>}"
log "keystore         : $STORE_FILE (alias $KEY_ALIAS)"
log "certificate      : $CERT"

if [ -z "$PROFILE_BUNDLE" ]; then
  warn "could not read bundle-name out of $PROFILE"
  warn "  (a .p7b is a PKCS#7 wrapper around a JSON profile; if this is a certificate profile"
  warn "   instead of a debug profile, hvigor will fail with 00303074)"
elif [ "$PROFILE_BUNDLE" != "$BUNDLE" ]; then
  die "the profile belongs to $PROFILE_BUNDLE, not $BUNDLE — hvigor would reject it with 00303074.
  Request a debug profile for $BUNDLE (DevEco Studio: File > Project Structure > Signing Configs >
  Automatically generate signature, or AGC: Certificates > Debug profile)."
fi

if [ -z "$DEVICE_IDS" ]; then
  warn "the profile lists no device UDID; installation will be refused unless the device is"
  warn "  authorized for this bundle"
else
  log "the profile authorizes these device UDIDs; anything else is refused at install time:"
  printf '    %s\n' $DEVICE_IDS
fi

if [ "$DRY_RUN" = 1 ]; then
  DRY_RUN_NOTE=" (dry run: not created)"
fi

# --------------------------------------------------------------------- password form for hvigor
# Both passwords have to reach build-profile.json5 in the form hvigor decrypts. Do this before the
# rewrite so a material problem stops here, not twenty minutes into a build (and with the file
# still intact). A dry run goes through the same path so it really is a full validation.
STORE_DIR="$(cd "$(dirname "$STORE_FILE")" && pwd)"
MATERIAL_LINK="$STORE_DIR/material"
CIPHER_NEEDED=0
for pw in "$STORE_PASSWORD" "$KEY_PASSWORD"; do
  [ -n "$pw" ] || continue
  is_devsign_cipher "$pw" || CIPHER_NEEDED=1
done

if [ "$CIPHER_NEEDED" = 1 ]; then
  [ -d "$DEVSIGN_MATERIAL" ] || die "a plaintext password was given but $DEVSIGN_MATERIAL does not exist.
  hvigor only accepts DevEco-encrypted passwords and derives the key from that directory.
  Pass --store-password with an already-encrypted value, or point --devsign-material at a DevEco
  installation's material directory (DevEco Studio creates it on the first automatic signature)."
  python3 "$CIPHER" check "$DEVSIGN_MATERIAL" || die "$DEVSIGN_MATERIAL cannot derive a work key"

  PLAIN_STORE="$STORE_PASSWORD"
  PLAIN_KEY="$KEY_PASSWORD"
  [ -n "$PLAIN_STORE" ] && STORE_PASSWORD="$(encrypt_password "$PLAIN_STORE")"
  [ -n "$PLAIN_KEY" ] && KEY_PASSWORD="$(encrypt_password "$PLAIN_KEY")"
  # Round-trip before writing: a wrong work key would otherwise surface as hvigor's generic
  # "keystore password was incorrect" much later.
  if [ -n "$PLAIN_STORE" ] && \
     [ "$(python3 "$CIPHER" decrypt "$DEVSIGN_MATERIAL" "$STORE_PASSWORD")" != "$PLAIN_STORE" ]; then
    die "encrypting the store password did not round-trip through $DEVSIGN_MATERIAL"
  fi
  unset PLAIN_STORE PLAIN_KEY
  log "passwords        : plaintext -> DevEco cipher (work key from $DEVSIGN_MATERIAL)"
  log "                   the ciphertext only decrypts on THIS machine; it is not a secret that"
  log "                   travels, and swapping it for a plaintext password would leak the real one"
fi

if [ -n "$STORE_PASSWORD" ]; then
  if [ -e "$MATERIAL_LINK" ] || [ -L "$MATERIAL_LINK" ]; then
    log "material         : $MATERIAL_LINK (already in place)"
  elif [ "$DRY_RUN" = 1 ]; then
    log "material         : would symlink $MATERIAL_LINK -> $DEVSIGN_MATERIAL${DRY_RUN_NOTE}"
  else
    ln -s "$DEVSIGN_MATERIAL" "$MATERIAL_LINK"
    log "material         : $MATERIAL_LINK -> $DEVSIGN_MATERIAL"
    log "                   (hvigor resolves the work key at <dirname(storeFile)>/material; DevEco does"
    log "                    the same with a symlink, and cangjie/.gitignore keeps it untracked)"
  fi
fi

if [ "$DRY_RUN" = 1 ]; then
  log "dry run: $BUILD_PROFILE left untouched"
  exit 0
fi

# Rewrite only the values of the `default` signing config, in place, keeping the file's comments and
# formatting (a JSON round-trip would drop them; build-profile.json5 is JSON5 with comments).
python3 - "$BUILD_PROFILE" "$PRODUCT" "$STORE_FILE" "$KEY_ALIAS" "$CERT" "$PROFILE" "$SIGN_ALG" \
         "$STORE_PASSWORD" "$KEY_PASSWORD" <<'PY'
import json, re, sys

(path, product, store_file, key_alias, cert, profile, sign_alg,
 store_password, key_password) = sys.argv[1:10]

text = open(path, encoding="utf-8").read()
values = {
    "storeFile": store_file,
    "keyAlias": key_alias,
    "certpath": cert,
    "profile": profile,
    "signAlg": sign_alg,
}
if store_password:
    values["storePassword"] = store_password
if key_password:
    values["keyPassword"] = key_password

missing = []
for key, value in values.items():
    pattern = re.compile(r'("%s"\s*:\s*)"[^"]*"' % re.escape(key))
    new_text, count = pattern.subn(lambda m: m.group(1) + json.dumps(value), text, count=1)
    if count == 0:
        missing.append(key)
    text = new_text

if missing:
    sys.exit("error: could not find %s in %s" % (", ".join(missing), path))

open(path, "w", encoding="utf-8").write(text)
print("updated %s" % path)
PY

log "signing material written to $BUILD_PROFILE (product=$PRODUCT)"
log "next: cangjie/scripts/harmony/assemble_hap.sh   # now reports STATUS: installable"
