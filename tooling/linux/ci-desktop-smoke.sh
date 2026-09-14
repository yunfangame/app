#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${GITHUB_ACTIONS:-} == true && $(uname -s) == Linux && $(id -u) != 0 ]]
app=$1
evidence=$2
mkdir -p "$evidence"
openbox >"$evidence/window-manager.log" 2>&1 &
wm_pid=$!
"$app" >"$evidence/application.log" 2>&1 &
app_pid=$!
cleanup() {
  kill "$app_pid" "$wm_pid" 2>/dev/null || true
  wait "$app_pid" "$wm_pid" 2>/dev/null || true
}
trap cleanup EXIT
for attempt in {1..30}; do
  kill -0 "$app_pid"
  if windows=$(xdotool search --onlyvisible --pid "$app_pid" 2>/dev/null); then
    break
  fi
  sleep 1
done
[[ -n ${windows:-} ]]
sleep 10
kill -0 "$app_pid"
scrot "$evidence/first-launch.png"
timeout 15 "$app" >>"$evidence/relaunch.log" 2>&1
sleep 2
kill -0 "$app_pid"
after=$(xdotool search --onlyvisible --pid "$app_pid")
[[ $after == "$windows" ]]
scrot "$evidence/relaunch.png"
if grep -Ei 'libsoup.*(already|using)|symbol lookup error|Unhandled exception|segmentation fault' "$evidence/application.log"; then
  exit 1
fi
printf '%s\n' 'Desktop launch and single-instance relaunch passed.'
