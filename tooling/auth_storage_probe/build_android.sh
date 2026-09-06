#!/bin/bash
set -euo pipefail
umask 077
cd -- "$(dirname -- "$0")"
probe_flutter="${FENGWO_PROBE_FLUTTER:-flutter}"
if ! command -v "$probe_flutter" >/dev/null 2>&1; then
  printf '%s\n' 'Set FENGWO_PROBE_FLUTTER to the Flutter 3.44.4 executable.' >&2
  exit 2
fi
if [ ! -d android/app ]; then
  "$probe_flutter" create --empty --no-pub --platforms=android --project-name=fengwo_auth_storage_probe --org=io.fengwo.testing .
fi
probe_source_sha="$(shasum -a 256 ../../lib/common/local_secret_store.dart | awk '{print $1}')"
probe_run_id="probe-android-$(date +%Y%m%d-%H%M%S)-$RANDOM"
printf 'Probe identity: %s\n' "$probe_run_id"
"$probe_flutter" pub get
"$probe_flutter" build apk --release --target=main.dart --target-platform=android-arm64 --dart-define="FENGWO_AUTH_PROBE_ID=$probe_run_id" --dart-define="FENGWO_AUTH_PROBE_SOURCE_SHA=$probe_source_sha"
printf '%s\n' 'Build only. Install only this independent probe on a designated test device, then launch it twice.'
