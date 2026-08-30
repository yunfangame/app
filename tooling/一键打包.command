#!/usr/bin/env bash
set -euo pipefail

repo_root="${FENGWO_REPO:-/Users/lilaibin/Documents/ChatGPT/vps/FlClash-v0.8.96}"
"$repo_root/tooling/package_fengwo_all.sh" "$@"
