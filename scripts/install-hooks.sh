#!/bin/bash
set -euo pipefail
umask 077

root="$(cd "$(dirname "$0")/.." && pwd)"
base="${HOME:?HOME is not set}/.config/nubrix"
bin="$base/bin"

fail() {
  echo "install-hooks: $*" >&2
  exit 1
}

sources=(
  "claude-plugin/scripts/nubrix-hook"
  "claude-plugin/scripts/nubrix-permission"
  "claude-plugin/scripts/nubrix-statusline"
  "cli/notchctl"
)

for rel in "${sources[@]}"; do
  [ -f "$root/$rel" ] || fail "missing $root/$rel"
  bash -n "$root/$rel" || fail "syntax error in $rel"
done

mkdir -p "$(dirname "$base")"
for dir in "$base" "$bin"; do
  [ ! -L "$dir" ] || fail "$dir is a symlink, refusing to continue"
  [ -d "$dir" ] || mkdir "$dir"
  [ "$(stat -f '%u' "$dir")" = "$(id -u)" ] || fail "$dir is not owned by you"
  chmod 700 "$dir"
done

for rel in "${sources[@]}"; do
  name="$(basename "$rel")"
  dest="$bin/$name"
  tmp="$(mktemp "$bin/.$name.XXXXXX")"
  cat "$root/$rel" > "$tmp"
  chmod 500 "$tmp"
  if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$tmp" "$dest" && [ "$(stat -f '%Lp' "$dest")" = "500" ]; then
    rm -f "$tmp"
    echo "unchanged  $dest"
  else
    mv -f "$tmp" "$dest"
    echo "installed  $dest"
  fi
done

quote() {
  case "$1" in
    *[[:space:]]*) printf '\\"%s\\"' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

hook_cmd="$(quote "$bin/nubrix-hook")"
perm_cmd="$(quote "$bin/nubrix-permission")"
status_cmd="$(quote "$bin/nubrix-statusline")"

events=(SessionStart UserPromptSubmit PreToolUse PostToolUse PostToolUseFailure PermissionRequest PermissionDenied Notification Stop StopFailure SessionEnd)

settings_file="$HOME/.claude/settings.json"
if [ "${NUBRIX_SHOW_SNIPPET:-0}" != "1" ] && [ -r "$settings_file" ] \
  && grep -qF "$bin/nubrix-hook" "$settings_file" && grep -qF "$bin/nubrix-statusline" "$settings_file"; then
  echo "~/.claude/settings.json already uses these scripts (NUBRIX_SHOW_SNIPPET=1 to print the snippet)."
  exit 0
fi

cat <<TXT

Add this to ~/.claude/settings.json (this script never edits it). Hook commands
point at the sealed copies above, not at the git checkout.

{
  "hooks": {
TXT

last=$(( ${#events[@]} - 1 ))
for i in "${!events[@]}"; do
  event="${events[$i]}"
  comma=","
  [ "$i" -eq "$last" ] && comma=""
  if [ "$event" = "PermissionRequest" ]; then
    cat <<TXT
    "PermissionRequest": [
      { "hooks": [
        { "type": "command", "command": "$hook_cmd", "async": true, "timeout": 5 },
        { "type": "command", "command": "$perm_cmd", "timeout": 125 }
      ] }
    ]$comma
TXT
  else
    cat <<TXT
    "$event": [ { "hooks": [ { "type": "command", "command": "$hook_cmd", "async": true, "timeout": 5 } ] } ]$comma
TXT
  fi
done

cat <<TXT
  },
  "statusLine": { "type": "command", "command": "$status_cmd" },
  "permissions": {
    "deny": ["Edit(~/.config/nubrix/**)", "Write(~/.config/nubrix/**)"]
  }
}

Notes:
- Drop the nubrix-permission entry to keep Claude Code's own permission dialogs only.
- "permissions.deny" is merged with your existing list; it stops Claude from editing the sealed scripts.
- Re-run this script after updating Nubrix to refresh the copies. Optional CLI: ln -sf "$bin/notchctl" ~/.local/bin/notchctl
TXT
