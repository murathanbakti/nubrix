#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

hook="$PWD/claude-plugin/scripts/nubrix-hook"
[[ -f "$hook" ]] || { echo "missing $hook" >&2; exit 2; }

work="$(mktemp -d)"
listener_pid=""
listener_port=""
captured_request=""
cleanup() {
  if [[ -n "$listener_pid" ]]; then
    kill "$listener_pid" 2>/dev/null || true
    wait "$listener_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$work/home"
token="$(printf '%064d' 0 | tr '0' 'a')"
hex="0123456789abcdef0123456789abcdef"
payload='{"hook_event_name":"SessionStart","session_id":"t","cwd":"/tmp"}'

start_listener() {
  local out="$1" attempt
  for attempt in 1 2 3 4 5 6 7 8; do
    listener_port=$((20000 + RANDOM % 30000))
    : > "$out"
    /usr/bin/nc -l 127.0.0.1 "$listener_port" < /dev/null > "$out" 2>/dev/null &
    listener_pid=$!
    local waited=0
    while (( waited < 40 )); do
      if /usr/sbin/lsof -nP -a -p "$listener_pid" -iTCP:"$listener_port" -sTCP:LISTEN >/dev/null 2>&1; then
        return 0
      fi
      kill -0 "$listener_pid" 2>/dev/null || break
      sleep 0.05
      waited=$((waited + 1))
    done
    kill "$listener_pid" 2>/dev/null || true
    wait "$listener_pid" 2>/dev/null || true
    listener_pid=""
  done
  return 1
}

capture() {
  local out="$work/request.txt"
  start_listener "$out" || { echo "could not start a listener" >&2; exit 2; }
  printf '%s %s %s\n' "$listener_port" "$token" "$$" > "$work/endpoint"

  local env_args=(HOME="$work/home" NUBRIX_DEV=1 NUBRIX_ENDPOINT_FILE="$work/endpoint")
  if [[ $# -gt 0 ]]; then
    env_args+=(WARP_FOCUS_URL="$1")
  fi
  printf '%s' "$payload" | env -i "${env_args[@]}" /bin/bash "$hook" >/dev/null 2>&1 || true

  local waited=0
  while kill -0 "$listener_pid" 2>/dev/null && (( waited < 40 )); do
    sleep 0.05
    waited=$((waited + 1))
  done
  kill "$listener_pid" 2>/dev/null || true
  wait "$listener_pid" 2>/dev/null || true
  listener_pid=""
  captured_request="$(cat "$out")"
}

pass=0
fail=0

check() {
  local name="$1" expect="$2" request="$3" value="${4-}"
  local ok=1 reason=""
  if ! grep -q '^POST /v1/claude/hook ' <<< "$request" || ! grep -qi "^Authorization: Bearer $token" <<< "$request"; then
    ok=0
    reason="no hook request captured"
  elif [[ "$expect" == present ]]; then
    if ! grep -qx "X-Nubrix-Focus-URL: $value"$'\r' <<< "$request" && ! grep -qx "X-Nubrix-Focus-URL: $value" <<< "$request"; then
      ok=0
      reason="header missing"
    fi
  else
    if grep -qi '^X-Nubrix-Focus-URL:' <<< "$request"; then
      ok=0
      reason="header present"
    fi
    if grep -qi '^X-Evil' <<< "$request"; then
      ok=0
      reason="injected header present"
    fi
  fi
  if (( ok )); then
    echo "PASS  $name"
    pass=$((pass + 1))
  else
    echo "FAIL  $name ($reason)"
    fail=$((fail + 1))
  fi
}

run_present() {
  local name="$1" value="$2"
  capture "$value"
  check "$name" present "$captured_request" "$value"
}

run_absent() {
  local name="$1"
  shift
  capture "$@"
  check "$name" absent "$captured_request"
}

run_present "warp:// 32 hex" "warp://session/$hex"
run_present "warppreview:// 32 hex" "warppreview://session/$hex"
run_present "warp + 12 letters scheme" "warpabcdefghijkl://session/$hex"

run_absent "unset"
run_absent "empty" ""
run_absent "uppercase hex" "warp://session/0123456789ABCDEF0123456789ABCDEF"
run_absent "31 hex" "warp://session/${hex:0:31}"
run_absent "33 hex" "warp://session/${hex}0"
run_absent "https scheme" "https://session/$hex"
run_absent "path suffix" "warp://session/$hex/x"
run_absent "query string" "warp://session/$hex?a=b"
run_absent "CRLF header injection" $'warp://session/'"$hex"$'\r\nX-Evil: 1'
run_absent "LF header injection" $'warp://session/'"$hex"$'\nX-Evil: 1'
run_absent "13 letter scheme" "warpabcdefghijklm://session/$hex"
run_absent "leading space" " warp://session/$hex"
run_absent "trailing space" "warp://session/$hex "
run_absent "other host" "warp://other/$hex"
run_absent "over 64 chars" "warp://session/${hex}${hex}"

echo
echo "---- hook header summary ----"
echo "passed: $pass, failed: $fail"
if (( fail == 0 )); then
  echo "PASS"
else
  echo "FAIL"
  exit 1
fi
