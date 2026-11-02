#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  scripts/setup-release-signing.sh csr
      Creates a private key and a certificate signing request for a
      Developer ID Application certificate.
  scripts/setup-release-signing.sh upload [--cer FILE] [--p8 FILE] [--issuer ID] [--yes] [--dry-run]
      Builds the .p12 from the downloaded certificate and uploads the
      release signing secrets to GitHub. Without --cer or --p8 it uses the
      newest matching file in ~/Downloads.

Files are kept in $NUBRIX_SIGNING_DIR (default ~/.nubrix-signing), never in
the repository. Secrets go to the repository of the origin remote, or $NUBRIX_REPO.
EOF
  exit 2
}

fail() {
  echo "setup-release-signing: $*" >&2
  exit 1
}

ssl=/usr/bin/openssl
dir="${NUBRIX_SIGNING_DIR:-$HOME/.nubrix-signing}"
root="$(cd "$(dirname "$0")/.." && pwd)"
umask 077

newest() {
  local pattern="$1" f best=""
  for f in $HOME/Downloads/$pattern; do
    [ -f "$f" ] || continue
    if [ -z "$best" ] || [ "$f" -nt "$best" ]; then best="$f"; fi
  done
  printf '%s' "$best"
}

cmd_csr() {
  mkdir -p "$dir"
  chmod 700 "$dir"
  local key="$dir/developer-id.key" csr="$dir/DeveloperID.certSigningRequest"
  if [ -f "$key" ]; then
    echo "Reusing the existing private key in $dir"
  else
    "$ssl" genrsa -out "$key" 2048 2>/dev/null
  fi
  "$ssl" req -new -key "$key" -out "$csr" -subj "/CN=Nubrix Developer ID/O=Nubrix" 2>/dev/null
  cp "$csr" "$HOME/Desktop/DeveloperID.certSigningRequest"
  echo "Certificate signing request: $HOME/Desktop/DeveloperID.certSigningRequest"
  echo "Upload it at https://developer.apple.com/account/resources/certificates/add (Developer ID Application, G2 Sub-CA),"
  echo "download the .cer, then run: scripts/setup-release-signing.sh upload"
}

cmd_upload() {
  local cer="" p8="" issuer="" dry=0 yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --cer) cer="${2:-}"; shift 2 ;;
      --p8) p8="${2:-}"; shift 2 ;;
      --issuer) issuer="${2:-}"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      --yes) yes=1; shift ;;
      *) usage ;;
    esac
  done

  local key="$dir/developer-id.key"
  [ -f "$key" ] || fail "no private key in $dir; run the csr step first"
  [ -n "$cer" ] || cer="$(newest 'developerID_application*.cer')"
  [ -n "$cer" ] || cer="$(newest '*.cer')"
  [ -f "$cer" ] || fail "certificate not found; pass --cer FILE"
  [ -n "$p8" ] || p8="$(newest 'AuthKey_*.p8')"
  [ -f "$p8" ] || fail "App Store Connect key not found; pass --p8 FILE"

  local pem="$dir/developer-id.pem"
  "$ssl" x509 -inform der -in "$cer" -out "$pem" 2>/dev/null || "$ssl" x509 -in "$cer" -out "$pem" 2>/dev/null \
    || fail "cannot read certificate $cer"

  local subject cn team
  subject="$("$ssl" x509 -in "$pem" -noout -subject -nameopt multiline)"
  cn="$(awk -F' = ' '/commonName/ { print $2; exit }' <<< "$subject")"
  team="$(awk -F' = ' '/organizationalUnitName/ { print $2; exit }' <<< "$subject")"
  [[ "$cn" == "Developer ID Application: "* ]] || fail "$cer is not a Developer ID Application certificate ($cn)"
  [[ "$team" =~ ^[A-Z0-9]{10}$ ]] || fail "cannot read the team ID from the certificate"

  local cert_mod key_mod
  cert_mod="$("$ssl" x509 -in "$pem" -noout -modulus | shasum -a 256)"
  key_mod="$("$ssl" rsa -in "$key" -noout -modulus 2>/dev/null | shasum -a 256)"
  [ "$cert_mod" = "$key_mod" ] || fail "the certificate does not belong to the private key in $dir; create it from the CSR this script made"

  local issuer_hash chain="$dir/chain.pem" all="$dir/all-ca.pem"
  issuer_hash="$("$ssl" x509 -in "$pem" -noout -issuer_hash)"
  : > "$chain"
  security find-certificate -a -p -c "Developer ID Certification Authority" > "$all" 2>/dev/null || true
  awk -v d="$dir" '/BEGIN CERT/ { n++ } { print > (d "/ca-" n ".pem") }' "$all"
  local ca
  for ca in "$dir"/ca-*.pem; do
    [ -f "$ca" ] || continue
    if [ "$("$ssl" x509 -in "$ca" -noout -subject_hash 2>/dev/null)" = "$issuer_hash" ]; then
      cat "$ca" > "$chain"
      break
    fi
  done
  rm -f "$dir"/ca-*.pem "$all"
  [ -s "$chain" ] || echo "Warning: the Developer ID intermediate certificate was not found in your keychains; the .p12 holds only your certificate." >&2

  local key_id
  key_id="$(basename "$p8" .p8)"
  key_id="${key_id#AuthKey_}"
  [[ "$key_id" =~ ^[A-Z0-9]{10}$ ]] || fail "cannot read the key ID from $(basename "$p8"); keep Apple's AuthKey_<KEYID>.p8 file name"
  grep -q 'BEGIN PRIVATE KEY' "$p8" || fail "$p8 is not an App Store Connect API key"

  if [ -z "$issuer" ]; then
    read -r -p "Issuer ID (shown above the key list in App Store Connect): " issuer
  fi
  issuer="$(tr -d '[:space:]' <<< "$issuer" | tr '[:upper:]' '[:lower:]')"
  [[ "$issuer" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || fail "the issuer ID must look like 69a6de7e-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

  local password p12="$dir/DeveloperID.p12"
  password="$("$ssl" rand -base64 24 | tr -d '/+=' | cut -c1-28)"
  local certfile=()
  [ -s "$chain" ] && certfile=(-certfile "$chain")
  "$ssl" pkcs12 -export -inkey "$key" -in "$pem" ${certfile[@]+"${certfile[@]}"} -name "$cn" \
    -out "$p12" -passout fd:3 3<<< "$password" 2>/dev/null || fail "could not build the .p12"

  local check="$dir/check.keychain-db" check_pw
  check_pw="$("$ssl" rand -hex 16)"
  rm -f "$check"
  security create-keychain -p "$check_pw" "$check" >/dev/null
  if ! security import "$p12" -k "$check" -f pkcs12 -P "$password" -T /usr/bin/codesign >/dev/null 2>&1; then
    security delete-keychain "$check" >/dev/null 2>&1 || true
    fail "macOS cannot import the generated .p12"
  fi
  security delete-keychain "$check" >/dev/null 2>&1 || true

  local repo="${NUBRIX_REPO:-}"
  if [ -z "$repo" ]; then
    repo="$(git -C "$root" remote get-url origin 2>/dev/null | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')"
  fi
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "cannot tell the GitHub repository; set NUBRIX_REPO=owner/name"

  echo "Certificate: $cn"
  echo "Team ID:     $team"
  echo "API key ID:  $key_id"
  echo "Repository:  $repo"

  if [ "$dry" = 1 ]; then
    echo "Dry run: nothing uploaded. The .p12 is in $dir"
    return
  fi

  if [ "$yes" != 1 ]; then
    local answer
    read -r -p "Upload the signing secrets to $repo? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || fail "nothing uploaded"
  fi

  base64 -i "$p12" | gh secret set DEVELOPER_ID_P12_BASE64 -R "$repo"
  printf '%s' "$password" | gh secret set DEVELOPER_ID_P12_PASSWORD -R "$repo"
  base64 -i "$p8" | gh secret set NOTARY_API_KEY_P8_BASE64 -R "$repo"
  printf '%s' "$key_id" | gh secret set NOTARY_API_KEY_ID -R "$repo"
  printf '%s' "$issuer" | gh secret set NOTARY_API_ISSUER_ID -R "$repo"
  gh variable set APPLE_TEAM_ID -R "$repo" --body "$team"

  cp "$p8" "$dir/$(basename "$p8")"
  printf '%s\n' "$password" > "$dir/DeveloperID.p12.password"
  rm -f "$HOME/Desktop/DeveloperID.certSigningRequest"
  echo
  echo "Uploaded the release signing secrets to $repo."
  echo "Backup in $dir: DeveloperID.p12, its password, the private key and $(basename "$p8")."
  echo "Copy that folder to your password manager or an encrypted disk, then delete $p8 and $cer from Downloads."
}

case "${1:-}" in
  csr) shift; cmd_csr "$@" ;;
  upload) shift; cmd_upload "$@" ;;
  *) usage ;;
esac
