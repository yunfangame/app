#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="${FENGWO_REPO:-/Users/lilaibin/Documents/ChatGPT/vps/FlClash-v0.8.96}"
source_path="${1:-$script_dir/ConFigOss4.source.json}"
output_path="${2:-$script_dir/ConFigOss4.json}"

"$repo_root/tooling/seal_remote_config.sh" "$source_path" "$output_path"
printf '已生成并验证：%s\n' "$output_path"
