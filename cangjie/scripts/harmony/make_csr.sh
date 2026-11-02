#!/usr/bin/env bash
# Generate the signing key pair (PKCS#12 keystore) and the PKCS#10 CSR that Huawei AGC needs to
# issue a debug certificate for this bundle.
#
# AGC owns the certificate chain: it takes the CSR, returns a .cer, and (once the device UDID is
# registered) a debug provisioning profile .p7b. This script produces the two local pieces and
# nothing else. It never talks to the network and never prints or commits the password.
#
# Usage:
#   cangjie/scripts/harmony/make_csr.sh [options]
#
#   --alias <name>          key alias and file stem (default: textura-debug)
#   --out-dir <dir>         output directory (default: cangjie/harmony/.certs/<alias>)
#   --dname <dn>            keytool-style subject (default: C=CN,O=EthanCheung,OU=Textura,CN=Textura Debug)
#   --validity <days>       validity of the local self-signed cert (default: 9125)
#   --password <value>      keystore/key password; prefer --password-file (argv is world-readable)
#   --password-file <file>  read the password from the first line of <file>
#   --openssl               use openssl instead of keytool
#   --force                 replace an existing .p12/.csr in --out-dir
#   -h, --help              print this help
#
# Password policy: when neither --password nor --password-file is given, an existing
# <out-dir>/password.txt is reused, otherwise a fresh 24-character random password is generated and
# written there (mode 600). The password itself is never echoed.
#
# Default route (keytool): EC P-256 (secp256r1) + SHA256withECDSA in a PKCS#12 keystore, which is
# what Huawei requires. --openssl builds the same key/CSR with openssl instead; it also puts a
# throwaway self-signed certificate in the p12 (the AGC .cer replaces it at signing time). The
# self-check always uses openssl and additionally cross-checks the p12 with keytool when available.
#
# Files written (all mode 600, directory mode 700):
#   <out-dir>/<alias>.p12          keystore with the private key (NEVER commit)
#   <out-dir>/<alias>.csr          PKCS#10 request to upload to AGC (public, but keep out of git)
#   <out-dir>/password.txt         only when the password was generated here (NEVER commit)
#
# Idempotent: without --force existing material is re-verified and left untouched; with --force it
# is regenerated atomically. cangjie/harmony/.certs/ is git-ignored — see cangjie/docs/HARMONY.md §7.1a.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

ALIAS="textura-debug"
OUT_DIR=""
DNAME="C=CN,O=EthanCheung,OU=Textura,CN=Textura Debug"
VALIDITY=9125
PASSWORD=""
PASSWORD_FILE=""
PASSWORD_FROM=""
FORCE=0
USE_OPENSSL=0

KEYTOOL="${KEYTOOL:-/usr/bin/keytool}"
OPENSSL="${OPENSSL:-/usr/bin/openssl}"
# keytool/openssl read the secret from the environment, so it never shows up in `ps` output.
PASS_ENV="TEXTURA_KEYSTORE_PASSWORD"
export "$PASS_ENV="

usage() {
  sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --alias)         ALIAS="${2:-}"; shift 2 ;;
    --out-dir)       OUT_DIR="${2:-}"; shift 2 ;;
    --dname)         DNAME="${2:-}"; shift 2 ;;
    --validity)      VALIDITY="${2:-}"; shift 2 ;;
    --password)      PASSWORD="${2:-}"; PASSWORD_FROM="--password"; shift 2 ;;
    --password-file) PASSWORD_FILE="${2:-}"; PASSWORD_FROM="file"; shift 2 ;;
    --openssl)       USE_OPENSSL=1; shift ;;
    --force)         FORCE=1; shift ;;
    -h|--help)       usage 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ -n "$ALIAS" ] || die "--alias must not be empty"
case "$ALIAS" in */*|*..*) die "--alias must be a plain file stem: $ALIAS" ;; esac
[ -n "$DNAME" ] || die "--dname must not be empty"
case "$VALIDITY" in ''|*[!0-9]*) die "--validity must be a number of days: $VALIDITY" ;; esac
[ "$VALIDITY" -gt 0 ] || die "--validity must be positive: $VALIDITY"
[ -n "$PASSWORD" ] && [ -n "$PASSWORD_FILE" ] && die "use either --password or --password-file, not both"

if [ "$USE_OPENSSL" = 1 ]; then
  [ -x "$OPENSSL" ] || OPENSSL="$(command -v openssl || true)"
  [ -n "$OPENSSL" ] && [ -x "$OPENSSL" ] || die "openssl not found"
  # keytool is optional on this route: it is only used for the alias/entry back-check.
  [ -x "$KEYTOOL" ] || KEYTOOL="$(command -v keytool || true)"
  [ -n "$KEYTOOL" ] && [ -x "$KEYTOOL" ] || KEYTOOL=""
else
  [ -x "$KEYTOOL" ] || KEYTOOL="$(command -v keytool || true)"
  [ -n "$KEYTOOL" ] && [ -x "$KEYTOOL" ] || die "keytool not found (install a JDK or pass --openssl)"
  [ -x "$OPENSSL" ] || OPENSSL="$(command -v openssl || true)"
  [ -n "$OPENSSL" ] && [ -x "$OPENSSL" ] || die "openssl is required for the self-check"
fi

OUT_DIR="${OUT_DIR:-$CJ_ROOT/harmony/.certs/$ALIAS}"
P12="$OUT_DIR/$ALIAS.p12"
CSR="$OUT_DIR/$ALIAS.csr"
PASSWORD_TXT="$OUT_DIR/password.txt"
BUNDLE="$(app_bundle_name || true)"
BUNDLE="${BUNDLE:-com.ethancheung.textura}"

umask 077
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

TMP_DIR=""
cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

# 24 chars, [A-Za-z0-9], at least one upper/lower/digit. Only alphanumerics: the value is safe in a
# shell, in JSON and in the DevEco password field, and 24 alphanumerics is ~143 bits of entropy.
generate_password() {
  local body upper lower digit
  body="$("$OPENSSL" rand -base64 64 | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-21)"
  upper="$("$OPENSSL" rand -base64 64 | LC_ALL=C tr -dc 'A-Z' | cut -c1)"
  lower="$("$OPENSSL" rand -base64 64 | LC_ALL=C tr -dc 'a-z' | cut -c1)"
  digit="$("$OPENSSL" rand -base64 64 | LC_ALL=C tr -dc '0-9' | cut -c1)"
  [ "${#body}" = 21 ] && [ -n "$upper" ] && [ -n "$lower" ] && [ -n "$digit" ] || return 1
  printf '%s%s%s%s' "$body" "$upper" "$lower" "$digit"
}

resolve_password() {
  local candidate=""
  if [ -n "$PASSWORD_FILE" ]; then
    require_file "$PASSWORD_FILE" "password file"
    candidate="$(head -1 "$PASSWORD_FILE" | tr -d '\r\n')"
    [ -n "$candidate" ] || die "$PASSWORD_FILE is empty"
    PASSWORD="$candidate"
    PASSWORD_FROM="$PASSWORD_FILE"
  elif [ -n "$PASSWORD" ]; then
    PASSWORD_FROM="--password (not stored on disk)"
  elif [ -f "$PASSWORD_TXT" ]; then
    candidate="$(head -1 "$PASSWORD_TXT" | tr -d '\r\n')"
    if [ -n "$candidate" ]; then
      PASSWORD="$candidate"
      PASSWORD_FROM="existing $PASSWORD_TXT"
      chmod 600 "$PASSWORD_TXT"
      log "reusing password from $PASSWORD_TXT"
    fi
  fi

  if [ -z "$PASSWORD" ]; then
    PASSWORD="$(generate_password)" || die "could not generate a random password"
    printf '%s\n' "$PASSWORD" > "$PASSWORD_TXT"
    chmod 600 "$PASSWORD_TXT"
    PASSWORD_FROM="$PASSWORD_TXT"
    log "generated a 24-character random password -> $PASSWORD_TXT (mode 600, not printed)"
  fi

  [ "${#PASSWORD}" -ge 6 ] || die "the keystore password must be at least 6 characters (PKCS#12)"
  export "$PASS_ENV=$PASSWORD"
}

# keytool writes a CRLF PEM with the legacy "NEW CERTIFICATE REQUEST" label. Normalise to LF and the
# standard PKCS#10 label; the DER (and therefore the signature and the fingerprint) is unchanged.
normalize_csr() {
  local csr="$1" tmp="$1.tmp"
  tr -d '\r' < "$csr" > "$tmp"
  sed -e 's/^-----BEGIN NEW CERTIFICATE REQUEST-----$/-----BEGIN CERTIFICATE REQUEST-----/' \
      -e 's/^-----END NEW CERTIFICATE REQUEST-----$/-----END CERTIFICATE REQUEST-----/' \
      "$tmp" > "$csr"
  rm -f "$tmp"
}

generate_keytool() {
  local dir="$1"
  local p12="$dir/$ALIAS.p12" csr="$dir/$ALIAS.csr"

  log "keytool: EC secp256r1 + SHA256withECDSA, PKCS#12, alias $ALIAS, validity $VALIDITY days"
  "$KEYTOOL" -genkeypair \
    -alias "$ALIAS" \
    -keyalg EC -groupname secp256r1 -sigalg SHA256withECDSA \
    -dname "$DNAME" -validity "$VALIDITY" \
    -storetype PKCS12 -keystore "$p12" \
    -storepass:env "$PASS_ENV" -keypass:env "$PASS_ENV" >/dev/null

  "$KEYTOOL" -certreq \
    -alias "$ALIAS" -keystore "$p12" -storetype PKCS12 \
    -sigalg SHA256withECDSA \
    -storepass:env "$PASS_ENV" -file "$csr" >/dev/null

  normalize_csr "$csr"
  "$OPENSSL" req -in "$csr" -noout -verify >/dev/null 2>&1 \
    || die "the generated CSR does not verify: $csr"
}

# The openssl fallback needs a certificate in the PKCS#12 store; a throwaway self-signed one is
# enough because hvigor is pointed at the AGC-issued .cer via set_signing_material.sh --cert.
generate_openssl() {
  local dir="$1"
  local p12="$dir/$ALIAS.p12" csr="$dir/$ALIAS.csr"
  local key="$dir/.key.pem" cert="$dir/.selfsigned.pem"
  local subj

  case "$DNAME" in
    /*) subj="$DNAME" ;;
    *)  subj="/$(printf '%s' "$DNAME" | sed 's/[[:space:]]*,[[:space:]]*/\//g')" ;;
  esac

  log "openssl: EC prime256v1 + SHA256withECDSA, PKCS#12, alias $ALIAS, validity $VALIDITY days"
  "$OPENSSL" ecparam -name prime256v1 -genkey -noout -out "$key" 2>/dev/null
  "$OPENSSL" req -new -sha256 -key "$key" -subj "$subj" -out "$csr" 2>/dev/null
  "$OPENSSL" req -x509 -sha256 -key "$key" -subj "$subj" -days "$VALIDITY" \
    -out "$cert" 2>/dev/null
  "$OPENSSL" pkcs12 -export -inkey "$key" -in "$cert" -name "$ALIAS" \
    -out "$p12" -passout "env:$PASS_ENV" 2>/dev/null
  rm -f "$key" "$cert"

  "$OPENSSL" req -in "$csr" -noout -verify >/dev/null 2>&1 \
    || die "the generated CSR does not verify: $csr"
}

colonize() {
  printf '%s' "$1" | tr -d ':' | tr 'a-f' 'A-F' \
    | sed 's/../&:/g; s/:$//'
}

# Read back everything AGC and hvigor will care about, and fail loudly on a key/CSR mismatch.
verify_material() {
  local p12="$1" csr="$2"
  local csr_text subject pub_alg curve nist sigalg csr_sha csr_pub p12_pub
  local alias entry cert_fp

  for f in "$p12" "$csr"; do
    require_file "$f" "generated material"
    [ -s "$f" ] || die "$f is empty"
  done

  csr_text="$("$OPENSSL" req -in "$csr" -noout -text 2>/dev/null)" \
    || die "openssl cannot parse $csr as a PKCS#10 request"
  subject="$("$OPENSSL" req -in "$csr" -noout -subject 2>/dev/null | sed 's/^subject=//')"
  pub_alg="$(printf '%s\n' "$csr_text" | sed -n 's/^[[:space:]]*Public Key Algorithm: //p' | head -1)"
  curve="$(printf '%s\n' "$csr_text" | sed -n 's/^[[:space:]]*ASN1 OID: //p' | head -1)"
  nist="$(printf '%s\n' "$csr_text" | sed -n 's/^[[:space:]]*NIST CURVE: //p' | head -1)"
  sigalg="$(printf '%s\n' "$csr_text" | sed -n 's/^[[:space:]]*Signature Algorithm: //p' | head -1)"
  csr_sha="$("$OPENSSL" req -in "$csr" -outform DER 2>/dev/null \
    | "$OPENSSL" dgst -sha256 -r 2>/dev/null | awk '{print $1}' || true)"

  [ "$pub_alg" = "id-ecPublicKey" ] \
    || die "CSR public key algorithm is '${pub_alg:-unknown}', expected id-ecPublicKey"
  case "$curve" in
    prime256v1|P-256) ;;
    *) die "CSR curve is '${curve:-unknown}', expected prime256v1 (P-256)" ;;
  esac
  [ "$sigalg" = "ecdsa-with-SHA256" ] \
    || die "CSR signature algorithm is '${sigalg:-unknown}', expected ecdsa-with-SHA256"

  # Prove the keystore opens with this password before comparing keys: a wrong password has to read
  # as "wrong password", not as a key mismatch.
  local keystore_desc
  if [ -n "$KEYTOOL" ]; then
    alias="$("$KEYTOOL" -list -v -keystore "$p12" -storetype PKCS12 \
      -storepass:env "$PASS_ENV" 2>/dev/null | sed -n 's/^Alias name: //p' | head -1 || true)"
    entry="$("$KEYTOOL" -list -v -keystore "$p12" -storetype PKCS12 \
      -storepass:env "$PASS_ENV" 2>/dev/null | sed -n 's/^Entry type: //p' | head -1 || true)"
    [ -n "$alias" ] || die "keytool cannot open $p12 (wrong password or not a PKCS#12 keystore)"
    [ "$(printf '%s' "$alias" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$ALIAS" | tr 'A-Z' 'a-z')" ] \
      || die "keystore alias is '$alias', expected '$ALIAS'"
    [ "$entry" = "PrivateKeyEntry" ] || die "keystore entry '$alias' is '$entry', expected PrivateKeyEntry"
    keystore_desc="$alias / $entry"
  else
    "$OPENSSL" pkcs12 -in "$p12" -nocerts -noout -passin "env:$PASS_ENV" >/dev/null 2>&1 \
      || die "openssl cannot open $p12 (wrong password or not a PKCS#12 keystore)"
    keystore_desc="$ALIAS / PrivateKeyEntry (keytool unavailable, not cross-checked)"
  fi

  # sha256 of empty input: what the pipelines below produce when the key cannot be extracted.
  local empty_sha="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  csr_pub="$("$OPENSSL" req -in "$csr" -pubkey -noout 2>/dev/null \
    | "$OPENSSL" pkey -pubin -outform DER 2>/dev/null \
    | "$OPENSSL" dgst -sha256 -r 2>/dev/null | awk '{print $1}' || true)"
  p12_pub="$("$OPENSSL" pkcs12 -in "$p12" -nocerts -nodes -passin "env:$PASS_ENV" 2>/dev/null \
    | "$OPENSSL" pkey -pubout -outform DER 2>/dev/null \
    | "$OPENSSL" dgst -sha256 -r 2>/dev/null | awk '{print $1}' || true)"

  [ -n "$csr_pub" ] && [ "$csr_pub" != "$empty_sha" ] \
    || die "could not read the public key out of $csr"
  [ -n "$p12_pub" ] && [ "$p12_pub" != "$empty_sha" ] \
    || die "could not read the private key out of $p12 (wrong password?)"
  if [ "$csr_pub" != "$p12_pub" ]; then
    die "keystore private key does not match the CSR public key
  p12 public key sha256 : $p12_pub
  csr public key sha256 : $csr_pub"
  fi

  cert_fp="$("$OPENSSL" pkcs12 -in "$p12" -nokeys -passin "env:$PASS_ENV" 2>/dev/null \
    | "$OPENSSL" x509 -noout -fingerprint -sha256 2>/dev/null \
    | sed 's/.*Fingerprint=//' || true)"

  printf '    CSR subject          : %s\n' "$subject"
  printf '    CSR public key       : %s / %s (%s)\n' "$pub_alg" "$curve" "${nist:-P-256}"
  printf '    CSR signature alg    : %s\n' "$sigalg"
  printf '    CSR SHA-256          : %s\n' "$(colonize "$csr_sha")"
  printf '    public key SHA-256   : %s\n' "$csr_pub"
  printf '    keystore key SHA-256 : %s  [matches CSR]\n' "$p12_pub"
  printf '    keystore alias/type  : %s\n' "$keystore_desc"
  printf '    keystore cert SHA-256: %s\n' "${cert_fp:-<none>}"
  printf '    keystore cert note   : local self-signed placeholder; AGC issues the real .cer\n'
}

# ---------------------------------------------------------------------------------------------
log "out-dir  : $OUT_DIR"
log "keystore : $P12 (PKCS#12, alias $ALIAS)"
log "CSR      : $CSR (PKCS#10, to upload to AGC)"

if [ -f "$P12" ] && [ -f "$CSR" ] && [ "$FORCE" = 0 ]; then
  resolve_password
  log "material already present; re-verifying (use --force to regenerate)"
  printf '==> self-check\n'
  verify_material "$P12" "$CSR"
  log "left untouched: $P12"
else
  resolve_password
  TMP_DIR="$(mktemp -d "$OUT_DIR/.make-csr.XXXXXX")"
  if [ "$USE_OPENSSL" = 1 ]; then
    generate_openssl "$TMP_DIR"
  else
    generate_keytool "$TMP_DIR"
  fi

  printf '==> self-check\n'
  verify_material "$TMP_DIR/$ALIAS.p12" "$TMP_DIR/$ALIAS.csr"

  mv -f "$TMP_DIR/$ALIAS.p12" "$P12"
  mv -f "$TMP_DIR/$ALIAS.csr" "$CSR"
  rm -rf "$TMP_DIR"
  TMP_DIR=""
  chmod 600 "$P12" "$CSR"
  if [ -f "$PASSWORD_TXT" ]; then
    chmod 600 "$PASSWORD_TXT"
  fi
  log "wrote $P12"
  log "wrote $CSR"
fi

PASSWORD_HINT="$PASSWORD_FROM"
if [ -f "$PASSWORD_TXT" ]; then
  if [ "$(head -1 "$PASSWORD_TXT" | tr -d '\r\n')" = "$PASSWORD" ]; then
    PASSWORD_HINT="$PASSWORD_TXT (mode 600, not printed)"
  else
    warn "$PASSWORD_TXT does not contain the password used for this keystore — update or delete it"
  fi
fi
log "password : $PASSWORD_HINT"

cat <<EOF

Next steps (AGC): bundleName must be $BUNDLE
  1. AppGallery Connect > Certificates > New certificate > type Debug
     upload: $CSR
     download the issued certificate (.cer)
  2. AppGallery Connect > Devices > register this device UDID:
       cangjie/scripts/harmony/device_udid.sh
     AppGallery Connect > Profiles > New profile > type Debug, bundleName $BUNDLE
     select the certificate from step 1 and the device above, download the .p7b
  3. wire the material into the project:
       cangjie/scripts/harmony/set_signing_material.sh \\
         --store-file $P12 \\
         --key-alias  $ALIAS \\
         --cert       <AGC>.cer \\
         --profile    <AGC>.p7b
  4. cangjie/scripts/harmony/assemble_hap.sh   # expect STATUS: installable

Keep the private key and password out of git: cangjie/harmony/.certs/ is git-ignored.
EOF

unset "$PASS_ENV"
