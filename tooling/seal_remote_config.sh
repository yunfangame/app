#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_path="${1:-$repo_root/tooling/remote_config/ConFigOss4.source.json}"
output_path="${2:-$repo_root/tooling/remote_config/ConFigOss4.json}"
keys_path="${3:-$repo_root/tooling/remote_config/keys.json}"
local_flutter="$(find "${repo_root}-toolchains" -maxdepth 4 -type f -path '*/flutter/bin/flutter' 2>/dev/null | sort | tail -1)"

if [[ -n "$local_flutter" ]]; then
  dart_bin="$(dirname "$local_flutter")/dart"
else
  dart_bin="$(command -v dart)"
fi

"$dart_bin" run "$repo_root/tooling/remote_config/remote_config_tool.dart" seal "$source_path" "$output_path" "$keys_path"
"$dart_bin" run "$repo_root/tooling/remote_config/remote_config_tool.dart" verify "$output_path" "$keys_path"
