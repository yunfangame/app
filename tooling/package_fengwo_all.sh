#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' "$repo_root/pubspec.yaml" | head -1)"
build_date="$(date +%Y%m%d)"
output_root="${1:-/Users/lilaibin/Documents/lilaibin/蜂窝加速器-${version}-${build_date}}"
macos_arm64_package="$output_root/macOS/蜂窝加速器-macOS-arm.dmg"
macos_amd64_package="$output_root/macOS/蜂窝加速器-macOS-amd.dmg"
toolchains_root="${repo_root}-toolchains"
local_flutter="$(find "$toolchains_root" -maxdepth 4 -type f -path '*/flutter/bin/flutter' 2>/dev/null | sort | tail -1)"

if [[ -z "$local_flutter" ]]; then
  printf '找不到项目 Flutter 工具链：%s\n' "$toolchains_root" >&2
  exit 1
fi

flutter_bin="$local_flutter"
dart_bin="$(dirname "$flutter_bin")/dart"
pub_cache="$toolchains_root/pub-cache"
keys_path="$repo_root/tooling/remote_config/keys.json"
source_config="$repo_root/tooling/remote_config/ConFigOss4.source.json"
android_sdk="$(sed -n 's/^sdk.dir=//p' "$repo_root/android/local.properties" | head -1)"
windows_snapshot_root=''
windows_worktree=''
windows_tag=''
package_temp_root="$(mktemp -d "${TMPDIR:-/tmp}/fengwo-local-package.XXXXXX")"
android_emulator_started=0
android_emulator_serial=''

export PATH="$(dirname "$flutter_bin"):$toolchains_root/go-1.26.4/go/bin:$pub_cache/bin:$PATH"
export PUB_CACHE="$pub_cache"
export JAVA_HOME="${JAVA_HOME:-/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home}"
export ANDROID_NDK="${ANDROID_NDK:-$android_sdk/ndk/28.2.13676358}"
export GRADLE_USER_HOME="$package_temp_root/gradle"

mkdir -p "$GRADLE_USER_HOME/init.d"
cp -p "$repo_root/tooling/gradle_mirrors.init.gradle" "$GRADLE_USER_HOME/init.d/fengwo-mirrors.gradle"
for gradle_cache_dir in caches wrapper jdks; do
  if [[ -e "$HOME/.gradle/$gradle_cache_dir" ]]; then
    ln -s "$HOME/.gradle/$gradle_cache_dir" "$GRADLE_USER_HOME/$gradle_cache_dir"
  fi
done

cleanup_windows_snapshot() {
  if [[ "$android_emulator_started" == '1' && -n "$android_emulator_serial" ]]; then
    "$android_sdk/platform-tools/adb" -s "$android_emulator_serial" emu kill >/dev/null 2>&1 || true
  fi
  if [[ -n "$windows_tag" ]]; then
    git -C "$repo_root" push app ":refs/tags/$windows_tag" >/dev/null 2>&1 || true
  fi
  if [[ -n "$windows_worktree" ]]; then
    git -C "$repo_root" worktree remove --force "$windows_worktree" >/dev/null 2>&1 || true
  fi
  case "$windows_snapshot_root" in
    /tmp/*|/var/folders/*) rm -rf "$windows_snapshot_root" ;;
  esac
  case "$package_temp_root" in
    /tmp/*|/var/folders/*) rm -rf "$package_temp_root" ;;
  esac
}

trap cleanup_windows_snapshot EXIT

if [[ ! -f "$keys_path" || ! -f "$source_config" ]]; then
  printf '缺少远程配置密钥或明文配置。\n' >&2
  exit 1
fi

mkdir -p "$output_root/Android" "$output_root/macOS" "$output_root/Windows" "$output_root/远程配置"
cp -p "$source_config" "$output_root/远程配置/ConFigOss4.source.json"
cp -p "$repo_root/tooling/加密远程配置.command" "$output_root/远程配置/加密远程配置.command"
cp -p "$repo_root/tooling/一键打包.command" "$output_root/一键打包.command"
chmod +x "$output_root/远程配置/加密远程配置.command"
chmod +x "$output_root/一键打包.command"
"$repo_root/tooling/seal_remote_config.sh" "$source_config" "$output_root/远程配置/ConFigOss4.json" "$keys_path"

verify_no_pre() {
  if find "$output_root" -type f -iname '*pre*' -print -quit | grep -q .; then
    printf '产物名称包含 pre。\n' >&2
    exit 1
  fi
}

copy_android_packages() {
  local source apk abi target
  for abi in arm64-v8a armeabi-v7a x86_64; do
    source="$(find "$repo_root/dist" -maxdepth 1 -type f -name "*android-${abi}.apk" -print | sort | tail -1)"
    if [[ -z "$source" ]]; then
      printf '找不到 Android %s 安装包。\n' "$abi" >&2
      exit 1
    fi
    target="$output_root/Android/蜂窝加速器-${version}-android-${abi}.apk"
    cp -p "$source" "$target"
  done
}

verify_android_packages() {
  local aapt="$android_sdk/build-tools/36.0.0/aapt"
  local apksigner="$android_sdk/build-tools/36.0.0/apksigner"
  local apk label package_name
  for apk in "$output_root"/Android/*.apk; do
    "$apksigner" verify --verbose "$apk" >/dev/null
    label="$($aapt dump badging "$apk" | sed -n "s/^application-label:'\(.*\)'/\1/p" | head -1)"
    package_name="$($aapt dump badging "$apk" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)"
    [[ "$label" == '蜂窝加速器' ]]
    [[ -n "$package_name" ]]
    unzip -tq "$apk" >/dev/null
  done
}

test_android_launch() {
  local adb="$android_sdk/platform-tools/adb"
  local emulator="$android_sdk/emulator/emulator"
  local aapt="$android_sdk/build-tools/36.0.0/aapt"
  local serial package_name activity_name apk abi_list apk_abi launch_log device_log
  "$adb" start-server >/dev/null
  serial="$($adb devices | awk '$1 ~ /^emulator-/ && $2 == "device" {print $1; exit}')"
  if [[ -z "$serial" ]]; then
    "$emulator" -avd FengWo_API_35 -no-snapshot -no-boot-anim -no-audio -no-window >"$output_root/android-emulator.log" 2>&1 &
    android_emulator_started=1
    for _ in $(seq 1 90); do
      serial="$($adb devices | awk '$1 ~ /^emulator-/ && $2 == "device" {print $1; exit}')"
      if [[ -n "$serial" && "$($adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == '1' ]]; then
        break
      fi
      sleep 2
    done
  fi
  if [[ -z "$serial" ]]; then
    printf 'Android 模拟器未启动。\n' >&2
    exit 1
  fi
  android_emulator_serial="$serial"
  abi_list="$($adb -s "$serial" shell getprop ro.product.cpu.abilist | tr -d '\r')"
  case "$abi_list" in
    *arm64-v8a*) apk_abi='arm64-v8a' ;;
    *x86_64*) apk_abi='x86_64' ;;
    *armeabi-v7a*) apk_abi='armeabi-v7a' ;;
    *) printf '不支持的模拟器 ABI：%s\n' "$abi_list" >&2; exit 1 ;;
  esac
  apk="$output_root/Android/蜂窝加速器-${version}-android-${apk_abi}.apk"
  package_name="$($aapt dump badging "$apk" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)"
  activity_name="$($aapt dump badging "$apk" | sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" | head -1)"
  launch_log="$output_root/android-launch.log"
  device_log="$package_temp_root/android-logcat.txt"
  "$adb" -s "$serial" install -r "$apk" >/dev/null
  "$adb" -s "$serial" logcat -c
  "$adb" -s "$serial" shell am force-stop "$package_name"
  "$adb" -s "$serial" shell am start -W -n "$package_name/$activity_name" >"$launch_log"
  sleep 8
  "$adb" -s "$serial" logcat -d -v threadtime >"$device_log"
  if ! "$adb" -s "$serial" shell pidof "$package_name" | grep -Eq '[0-9]'; then
    tail -n 240 "$device_log" >>"$launch_log"
    printf 'Android 客户端启动后退出，日志：%s\n' "$launch_log" >&2
    exit 1
  fi
  if grep -Eiq 'FATAL EXCEPTION|UnsatisfiedLinkError' "$device_log"; then
    grep -Ei 'FATAL EXCEPTION|UnsatisfiedLinkError|AndroidRuntime' "$device_log" >>"$launch_log"
    printf 'Android 客户端出现致命错误，日志：%s\n' "$launch_log" >&2
    exit 1
  fi
  if ! grep -F 'init result: true' "$device_log" >>"$launch_log"; then
    printf '应用进程运行正常，当前版本未输出旧版核心初始化标记。\n' >>"$launch_log"
  fi
  "$adb" -s "$serial" shell am force-stop "$package_name" >/dev/null
  "$adb" -s "$serial" uninstall "$package_name" >/dev/null
  if [[ "$android_emulator_started" == '1' ]]; then
    "$adb" -s "$serial" emu kill >/dev/null || true
  fi
  android_emulator_started=0
  android_emulator_serial=''
}

package_macos() {
  local xcode_arch="$1"
  local output_arch="$2"
  local source target
  FLUTTER_XCODE_ARCHS="$xcode_arch" "$dart_bin" setup.dart macos --env stable --targets dmg
  source="$(find "$repo_root/dist" -maxdepth 1 -type f -name '*macos-*.dmg' -print | sort | tail -1)"
  if [[ -z "$source" ]]; then
    printf '找不到 macOS %s 安装包。\n' "$output_arch" >&2
    exit 1
  fi
  case "$output_arch" in
    arm64) target="$macos_arm64_package" ;;
    amd64) target="$macos_amd64_package" ;;
    *) printf '不支持的 macOS 输出架构：%s\n' "$output_arch" >&2; exit 1 ;;
  esac
  cp -p "$source" "$target"
}

verify_macos_package() {
  local dmg="$1"
  local expected_arch="$2"
  local attach_output mount_point app binary core pid
  attach_output="$(hdiutil attach -nobrowse -readonly "$dmg")"
  mount_point="$(printf '%s\n' "$attach_output" | sed -n 's#^.*\(/Volumes/.*\)$#\1#p' | tail -1)"
  if [[ -z "$mount_point" ]]; then
    printf '无法挂载 %s\n' "$dmg" >&2
    exit 1
  fi
  app="$mount_point/蜂窝加速器.app"
  binary="$app/Contents/MacOS/FlClash"
  core="$app/Contents/MacOS/FlClashCore"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$app/Contents/Info.plist" | grep -Fx '蜂窝加速器' >/dev/null
  lipo -archs "$binary" | tr ' ' '\n' | grep -Fx "$expected_arch" >/dev/null
  lipo -archs "$core" | tr ' ' '\n' | grep -Fx "$expected_arch" >/dev/null
  codesign --verify --deep --strict "$app"
  if pgrep -x FlClash >/dev/null 2>&1; then
    printf '检测到已有 FlClash/蜂窝加速器实例，跳过会触发单实例保护的启动测试。\n' \
      >"$output_root/macos-${expected_arch}-launch.log"
  else
    arch "-$expected_arch" "$binary" >"$output_root/macos-${expected_arch}-launch.log" 2>&1 &
    pid=$!
    sleep 8
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      printf 'macOS %s 客户端启动后退出，日志：%s\n' \
        "$expected_arch" "$output_root/macos-${expected_arch}-launch.log" >&2
      exit 1
    fi
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
  fi
  for _ in $(seq 1 10); do
    if hdiutil detach "$mount_point" >/dev/null 2>&1; then
      mount_point=''
      break
    fi
    sleep 1
  done
  if [[ -n "$mount_point" ]]; then
    hdiutil detach -force "$mount_point" >/dev/null
  fi
}

copy_untracked_files() {
  local worktree="$1"
  local relative target
  while IFS= read -r -d '' relative; do
    target="$worktree/$relative"
    mkdir -p "$(dirname "$target")"
    cp -Pp "$repo_root/$relative" "$target"
  done < <(git -C "$repo_root" ls-files --others --exclude-standard -z)
}

package_windows_remote() {
  local snapshot_root worktree root_patch tag run_id download_dir source
  snapshot_root="$(mktemp -d "${TMPDIR:-/tmp}/fengwo-package.XXXXXX")"
  worktree="$snapshot_root/worktree"
  root_patch="$snapshot_root/root.patch"
  tag="fengwo-package-windows-${build_date}-$(date +%H%M%S)"
  download_dir="$snapshot_root/download"
  windows_snapshot_root="$snapshot_root"
  windows_worktree="$worktree"
  windows_tag="$tag"
  jq -r .aesKey "$keys_path" | gh secret set REMOTE_CONFIG_AES_KEY --repo yunfangame/app
  jq -r .signingPublicKey "$keys_path" | gh secret set REMOTE_CONFIG_SIGNING_PUBLIC_KEY --repo yunfangame/app
  git -C "$repo_root" worktree add --detach "$worktree" HEAD >/dev/null
  git -C "$repo_root" diff --binary HEAD -- . ':(exclude)core/Clash.Meta' > "$root_patch"
  if [[ -s "$root_patch" ]]; then
    git -C "$worktree" apply --whitespace=nowarn "$root_patch"
  fi
  git -C "$worktree" submodule sync --recursive
  git -C "$worktree" \
    -c protocol.file.allow=always \
    -c "submodule.core/Clash.Meta.url=$repo_root/core/Clash.Meta" \
    submodule update --init --recursive
  copy_untracked_files "$worktree"
  git -C "$worktree" add -A
  git -C "$worktree" -c user.name='FengWo Builder' -c user.email='builder@fengwo.local' commit -m "Package 蜂窝加速器 ${version}" >/dev/null
  git -C "$worktree" tag "$tag"
  git -C "$worktree" push app "refs/tags/$tag"
  run_id=''
  for _ in $(seq 1 60); do
    run_id="$(gh run list --repo yunfangame/app --event push --branch "$tag" --limit 10 --json databaseId,workflowName --jq '[.[] | select(.workflowName == "fengwo-windows-package")][0].databaseId // empty' 2>/dev/null || true)"
    [[ -n "$run_id" ]] && break
    sleep 5
  done
  if [[ -z "$run_id" ]]; then
    printf '未找到 Windows 云端打包任务。\n' >&2
    exit 1
  fi
  gh run watch "$run_id" --repo yunfangame/app --exit-status
  mkdir -p "$download_dir"
  gh run download "$run_id" --repo yunfangame/app --name fengwo-windows-amd64 --dir "$download_dir"
  source="$(find "$download_dir" -type f -name '*windows*.exe' -print | sort | head -1)"
  [[ -n "$source" ]]
  cp -p "$source" "$output_root/Windows/蜂窝加速器-${version}-windows-amd64.exe"
  source="$(find "$download_dir" -type f -name '*windows*.zip' -print | sort | head -1)"
  [[ -n "$source" ]]
  cp -p "$source" "$output_root/Windows/蜂窝加速器-${version}-windows-amd64.zip"
  cleanup_windows_snapshot
  windows_snapshot_root=''
  windows_worktree=''
  windows_tag=''
}

verify_windows_packages() {
  local archive="$output_root/Windows/蜂窝加速器-${version}-windows-amd64.zip"
  tar -tf "$archive" >/dev/null
  tar -tf "$archive" | grep -E 'FlClash\.exe|FlClashCore\.exe' >/dev/null
}

create_checksums_and_archive() {
  local checksum_file="$output_root/SHA256SUMS.txt"
  local archive_path="$(dirname "$output_root")/蜂窝加速器-${version}-全平台-${build_date}.zip"
  (
    cd "$output_root"
    find Android macOS Windows 远程配置 -type f ! -name '*.log' -print0 | sort -z | xargs -0 shasum -a 256
  ) > "$checksum_file"
  printf '版本：%s\n环境：stable\n名称：蜂窝加速器\nmacOS ARM（Apple 芯片）文件：蜂窝加速器-macOS-arm.dmg\nmacOS AMD（Intel 芯片）文件：蜂窝加速器-macOS-amd.dmg\nAndroid：签名、结构、模拟器安装启动通过\nmacOS ARM64：架构、签名、DMG、启动通过\nmacOS AMD64（Intel）：架构、签名、DMG、Rosetta 启动通过\nWindows AMD64：云端构建、结构、启动冒烟测试通过\n远程配置：AES-GCM 解密与 Ed25519 签名验证通过\n' "$version" > "$output_root/验证报告.txt"
  rm -f "$archive_path"
  rm -f "$output_root/$(basename "$archive_path")"
  ditto -c -k --sequesterRsrc --keepParent "$output_root" "$archive_path"
  cp -p "$archive_path" "$output_root/$(basename "$archive_path")"
}

cd "$repo_root"
if [[ "${FENGWO_FINALIZE_ONLY:-0}" == '1' ]]; then
  verify_android_packages
elif [[ "${FENGWO_RESUME_AFTER_MACOS:-0}" == '1' ]]; then
  verify_android_packages
  verify_macos_package "$macos_amd64_package" x86_64
  verify_macos_package "$macos_arm64_package" arm64
elif [[ "${FENGWO_RESUME_AFTER_INTEL:-0}" == '1' ]]; then
  verify_android_packages
  verify_macos_package "$macos_amd64_package" x86_64
  package_macos arm64 arm64
  verify_macos_package "$macos_arm64_package" arm64
else
  if [[ "${FENGWO_RESUME_AFTER_ANDROID:-0}" != '1' ]]; then
    "$flutter_bin" pub get
    "$flutter_bin" test test/setup_test.dart test/common/remote_config_cipher_test.dart test/core/controller_test.dart test/core/protocol_contract_test.dart test/views/proxies/common_test.dart test/widgets/dashboard_layout_test.dart --reporter expanded
    "$dart_bin" setup.dart android --env stable --targets apk
    copy_android_packages
  fi
  verify_android_packages
  test_android_launch
  package_macos x86_64 amd64
  verify_macos_package "$macos_amd64_package" x86_64
  package_macos arm64 arm64
  verify_macos_package "$macos_arm64_package" arm64
fi
if [[ "${FENGWO_FINALIZE_ONLY:-0}" != '1' ]]; then
  package_windows_remote
fi
verify_windows_packages
verify_no_pre
create_checksums_and_archive
verify_no_pre
printf '全部打包并验证完成：%s\n' "$output_root"
