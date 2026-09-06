#!/bin/bash
set -euo pipefail
umask 077
cd -- "$(dirname -- "$0")"
probe_flutter="${FENGWO_PROBE_FLUTTER:-flutter}"
if ! command -v "$probe_flutter" >/dev/null 2>&1; then
  printf '%s\n' 'Set FENGWO_PROBE_FLUTTER to the Flutter 3.44.4 executable.' >&2
  exit 2
fi
if [ ! -d macos/Runner.xcodeproj ]; then
  "$probe_flutter" create --empty --no-pub --platforms=macos --project-name=fengwo_auth_storage_probe --org=io.fengwo.testing .
fi
probe_source_sha="$(shasum -a 256 ../../lib/common/local_secret_store.dart | awk '{print $1}')"
"$probe_flutter" pub get
"$probe_flutter" build macos --release --target=main.dart --dart-define=MACOS_FILE_SECRET_STORAGE=true --dart-define="FENGWO_AUTH_PROBE_SOURCE_SHA=$probe_source_sha"
probe_run_id="probe-$(date +%Y%m%d-%H%M%S)-$RANDOM"
probe_executable='build/macos/Build/Products/Release/fengwo_auth_storage_probe.app/Contents/MacOS/fengwo_auth_storage_probe'
mkdir -p .results
probe_status=0
for probe_phase in seed reopen; do
  if ! FENGWO_AUTH_PROBE_ID="$probe_run_id" FENGWO_AUTH_PROBE_PHASE="$probe_phase" "$probe_executable" 2>&1 | tee ".results/$probe_run_id-$probe_phase.log"; then
    probe_status=1
  fi
done
printf 'Reports: %s/.results/%s-*\n' "$PWD" "$probe_run_id"
exit "$probe_status"
