#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF2'
usage: scripts/setup-sparkle-key.sh [--env NAME] [--account NAME] [--backup] [--yes]

Creates (or reuses) Nubrix's Sparkle EdDSA key in your login keychain, stores
the private key as SPARKLE_ED_PRIVATE_KEY in the GitHub environment NAME
(default release) without printing it, and writes the public key into
Nubrix/Info.plist as SUPublicEDKey.

  --env NAME      GitHub environment for the secret (default release)
  --account NAME  keychain account of the key (default nubrix)
  --backup        also export the private key to ~/.nubrix-signing/sparkle-ed25519.key
  --yes           skip the confirmation prompt

Run it yourself in a terminal. The private key never reaches the terminal,
the command line or the repository. Secrets go to the repository of the origin
remote, or $NUBRIX_REPO.
EOF2
  exit 2
}

fail() {
  echo "setup-sparkle-key: $*" >&2
  exit 1
}

root="$(cd "$(dirname "$0")/.." && pwd)"
plist="$root/Nubrix/Info.plist"
umask 077

env_name="release" account="nubrix" backup=0 yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --env | --account)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$1" in
        --env) env_name="$2" ;;
        --account) account="$2" ;;
      esac
      shift 2
      ;;
    --backup) backup=1; shift ;;
    --yes) yes=1; shift ;;
    *) usage ;;
  esac
done
[[ "$env_name" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "invalid environment name '$env_name'"
[[ "$account" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "invalid keychain account '$account'"

repository() {
  local repo="${NUBRIX_REPO:-}"
  if [ -z "$repo" ]; then
    repo="$(git -C "$root" remote get-url origin 2>/dev/null | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##' || true)"
  fi
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "cannot tell the GitHub repository; set NUBRIX_REPO=owner/name"
  printf '%s' "$repo"
}

confirm() {
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || fail "nothing changed"
}

[ -f "$plist" ] || fail "missing $plist"
repo="$(repository)"

gh auth status >/dev/null 2>&1 || fail "gh is not signed in; run: gh auth login"
gh api "repos/$repo/environments/$env_name" >/dev/null 2>&1 \
  || fail "environment '$env_name' does not exist in $repo; run: scripts/setup-release-signing.sh environment $env_name"

work="$(mktemp -d "${TMPDIR:-/tmp}/nubrix-sparkle-key.XXXXXX")"
trap 'if [ -f "$work/private-key" ]; then rm -P "$work/private-key" 2>/dev/null || true; fi; rm -rf "$work"' EXIT

tools="$("$root/scripts/sparkle-tools.sh" "$work/tools")"

if ! pub="$("$tools/generate_keys" --account "$account" -p 2>/dev/null)"; then
  "$tools/generate_keys" --account "$account" >/dev/null 2>&1 || fail "generate_keys could not create a key for account '$account'"
  pub="$("$tools/generate_keys" --account "$account" -p 2>/dev/null)" || fail "generate_keys could not read the public key"
fi
pub="$(printf '%s' "$pub" | tr -d '[:space:]')"
[[ "$pub" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "unexpected public key format"

current="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" 2>/dev/null || true)"
if [ -n "$current" ] && [ "$current" != "$pub" ]; then
  fail "Nubrix/Info.plist has a different SUPublicEDKey. Replacing it stops updates for installed copies (Sparkle rotates EdDSA keys only through a Developer ID signed DMG). Import the old key with generate_keys --account $account -f <file> instead."
fi

[ "$yes" = 1 ] || confirm "Store the private key as SPARKLE_ED_PRIVATE_KEY in $repo, environment $env_name, and write the public key into Nubrix/Info.plist?"

"$tools/generate_keys" --account "$account" -x "$work/private-key" >/dev/null 2>&1 || fail "could not export the private key"
[ -s "$work/private-key" ] || fail "the exported private key is empty"
gh secret set SPARKLE_ED_PRIVATE_KEY -R "$repo" --env "$env_name" < "$work/private-key" >/dev/null \
  || fail "could not store SPARKLE_ED_PRIVATE_KEY in $repo ($env_name)"
rm -P "$work/private-key"

if [ "$backup" = 1 ]; then
  backup_dir="${NUBRIX_SIGNING_DIR:-$HOME/.nubrix-signing}"
  mkdir -p "$backup_dir"
  chmod 700 "$backup_dir"
  "$tools/generate_keys" --account "$account" -x "$backup_dir/sparkle-ed25519.key" >/dev/null 2>&1 \
    || fail "could not write the backup (an existing $backup_dir/sparkle-ed25519.key is never overwritten)"
  chmod 600 "$backup_dir/sparkle-ed25519.key"
  echo "Backup: $backup_dir/sparkle-ed25519.key"
  echo "Copy $backup_dir to your password manager or an encrypted disk, as for the Developer ID backup."
fi

if [ -z "$current" ]; then
  if /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $pub" "$plist"
  else
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $pub" "$plist"
  fi
fi
[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" = "$pub" ] || fail "could not write SUPublicEDKey into Nubrix/Info.plist"

echo "Sparkle public key (SUPublicEDKey): $pub"
echo "Written to Nubrix/Info.plist"
echo "Private key: login keychain (account $account) and GitHub secret SPARKLE_ED_PRIVATE_KEY (environment $env_name)."
echo "Now commit Nubrix/Info.plist."
