#!/bin/bash

fw_log() {
  printf '%s\n' "$*"
  printf '%s %s\n' "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$FW_LOG_DIR/report.txt"
}

fw_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

fw_snapshot() {
  local phase state stage reason status
  phase=$1
  state="$FW_LOG_DIR/$phase.json"
  "$FW_PROBE" snapshot > "$state" 2>> "$FW_LOG_DIR/probe.stderr"
  status=$?
  if [ "$status" != 0 ]; then
    stage=$(fw_value "$state" failure.stage) || stage=unknown
    reason=$(fw_value "$state" failure.reason) || reason=unknown
    fw_log "SNAPSHOT phase=$phase failed stage=$stage reason=$reason probe_exit=$status"
  fi
  return "$status"
}

fw_baseline_clear() {
  [ "$(fw_value "$1" configuredProxyActive)" = false ] &&
    [ "$(fw_value "$1" tunRouteObserved)" = false ]
}

fw_restored() {
  local key before after
  fw_baseline_clear "$2" || return 1
  for key in primaryServiceDigest logicalDigest routeDigest; do
    before=$(fw_value "$1" "$key") || return 1
    after=$(fw_value "$2" "$key") || return 1
    [ -n "$before" ] && [ "$before" = "$after" ] || return 1
  done
}

fw_https() {
  local phase code
  phase=$1
  shift
  code=$(/usr/bin/curl --silent --show-error --fail --connect-timeout 8 --max-time 20 \
    --output /dev/null --write-out '%{http_code}' "$@" \
    'https://www.apple.com/library/test/success.html' 2> "$FW_LOG_DIR/https-$phase.stderr") || {
      fw_log "HTTPS phase=$phase failed; see https-$phase.stderr"
      return 1
    }
  case "$code" in
    2[0-9][0-9]) fw_log "HTTPS phase=$phase code=$code verified" ;;
    *) fw_log "HTTPS phase=$phase code=$code not_verified"; return 1 ;;
  esac
}

fw_prompt() {
  printf '%s\n' "$1"
  IFS= read -r FW_REPLY || return 1
}

fw_app_running() {
  /usr/bin/pgrep -x FengWoProxyTest >/dev/null 2>&1
}

fw_other_client_running() {
  /usr/bin/pgrep -x FengWo >/dev/null 2>&1 || /usr/bin/pgrep -x FlClash >/dev/null 2>&1
}

fw_phase() {
  local phase since attempt state audit
  phase=$1
  since=$2
  state="$FW_LOG_DIR/$phase.json"
  audit="$FW_LOG_DIR/$phase-events.json"
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    fw_snapshot "$phase" || return 1
    "$FW_PROBE" audit "$FW_EVENTS" "$since" "$phase" > "$audit" 2>> "$FW_LOG_DIR/probe.stderr" || return 1
    if [ "$(fw_value "$audit" matched)" = true ]; then
      if [ "$phase" = connected ]; then
        if [ "$(fw_value "$state" loopbackProxyVerified)" = true ] &&
          [ "$(fw_value "$state" proxyPort)" = 17981 ] &&
          [ "$(fw_value "$state" tunRouteObserved)" = false ] &&
          [ "$(fw_value "$state" primaryServiceDigest)" = "$(fw_value "$FW_LOG_DIR/before.json" primaryServiceDigest)" ] &&
          [ "$(fw_value "$state" routeDigest)" = "$(fw_value "$FW_LOG_DIR/before.json" routeDigest)" ]; then
          fw_log "PHASE $phase system_readback_and_client_event=verified"
          return 0
        fi
      elif fw_restored "$FW_LOG_DIR/before.json" "$state"; then
        if [ "$phase" != quit ] || ! fw_app_running; then
          fw_log "PHASE $phase baseline_restored_and_client_event=verified"
          return 0
        fi
      fi
    fi
    [ "$attempt" = 10 ] || /bin/sleep 1
  done
  fw_log "NOT_VERIFIED phase=$phase; no forced cleanup or further configuration writes"
  return 1
}

fw_finalize() {
  local status=$?
  if [ -n "${FW_EVENTS:-}" ] && [ -x "${FW_PROBE:-}" ]; then
    "$FW_PROBE" audit "$FW_EVENTS" "${FW_STARTED:-0}" collect > "$FW_LOG_DIR/lifecycle-events.json" 2>> "$FW_LOG_DIR/probe.stderr" || true
  fi
  fw_log "RESULT=${FW_RESULT:-NOT_VERIFIED} exit=$status"
  fw_log "日志目录：$FW_LOG_DIR"
  if fw_app_running; then
    fw_log '测试副本仍在运行，请在副本中断开并退出。脚本不会强制结束进程或清空其他软件的代理。'
  fi
}

fw_verify_inputs() {
  local expected actual bundle executable scheme
  [ -f "$FW_ROOT/probe.sha256" ] && [ -x "$FW_PROBE" ] && [ -d "$FW_APP" ] || return 1
  IFS= read -r expected < "$FW_ROOT/probe.sha256" || return 1
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
  actual=$(/usr/bin/shasum -a 256 "$FW_PROBE" | /usr/bin/awk '{print $1}') || return 1
  [ "$actual" = "$expected" ] || return 1
  /usr/bin/codesign --verify --deep --strict "$FW_APP" > "$FW_LOG_DIR/signature.txt" 2>&1 || return 1
  bundle=$(fw_value "$FW_APP/Contents/Info.plist" CFBundleIdentifier) || return 1
  executable=$(fw_value "$FW_APP/Contents/Info.plist" CFBundleExecutable) || return 1
  scheme=$(fw_value "$FW_APP/Contents/Info.plist" CFBundleURLTypes.0.CFBundleURLSchemes.0) || return 1
  [ "$bundle" = com.fengwo.accelerator.proxytest ] && [ "$executable" = FengWoProxyTest ] && [ "$scheme" = fengwo-proxytest ]
}

fw_run() {
  local mode since
  mode=${1:-interactive}
  case "$mode" in interactive|--diagnose-only) ;; *) fw_log 'STOP: unknown argument'; return 2 ;; esac
  [ "$(/usr/bin/uname -s)" = Darwin ] && [ "$(/usr/bin/id -u)" != 0 ] || {
    fw_log 'STOP: 仅限 macOS 普通用户运行，不要使用 sudo。'
    return 2
  }
  fw_log '蜂窝 Mac 授权修复隔离验证工具（客户测试版，未完成实机验收）'
  fw_log '不会安装或覆盖正式客户端，不会修改 sudoers、授权策略、DNS 或其他代理软件。'
  fw_verify_inputs || { fw_log 'STOP: 隔离副本身份、签名或探测工具校验失败。'; return 3; }
  fw_snapshot before || { fw_log 'STOP: 无法取得完整的只读基线。'; return 4; }
  if [ "$mode" = --diagnose-only ]; then
    FW_RESULT=DIAGNOSE_ONLY
    fw_log 'DIAGNOSE_ONLY: 已保存只读摘要，没有启动客户端或请求授权，不代表连接验收通过。'
    return 0
  fi
  fw_baseline_clear "$FW_LOG_DIR/before.json" || {
    fw_log 'STOP: 检测到已有代理或 TUN 路由。请换隔离 Mac 验收；工具不会关闭现有代理。'
    return 5
  }
  if fw_app_running || fw_other_client_running || /usr/sbin/lsof -nP -iTCP:17981 -sTCP:LISTEN -t >/dev/null 2>&1; then
    fw_log 'STOP: 蜂窝或 FlClash 已运行，或隔离端口 17981 被占用。请先正常退出其他客户端。'
    return 5
  fi
  fw_https before --proxy '' --noproxy '*' || return 6
  fw_prompt '本工具将启动隔离副本。仅在隔离 Mac 验收；使用测试账号，保持系统代理模式和端口 17981，不要开启 TUN。输入 TEST 继续：' || return 7
  [ "$FW_REPLY" = TEST ] || return 7
  /usr/bin/open -n "$FW_APP" || return 7
  since=$(/bin/date +%s)
  fw_prompt '请在“蜂窝授权验证”中登录测试账号并连接。系统请求授权时，在系统窗口输入本机管理员密码，不要发送密码。显示已连接后按回车：' || return 7
  fw_phase connected "$since" && fw_https connected --proxy http://127.0.0.1:17981 --noproxy '' || return 8
  since=$(/bin/date +%s)
  fw_prompt '请在隔离副本中点击断开连接，完成后按回车：' || return 7
  fw_phase disconnected "$since" && fw_https disconnected --proxy '' --noproxy '*' || return 9
  since=$(/bin/date +%s)
  fw_prompt '请在隔离副本中再次连接，完成后按回车：' || return 7
  fw_phase connected "$since" && fw_https reconnected --proxy http://127.0.0.1:17981 --noproxy '' || return 8
  since=$(/bin/date +%s)
  fw_prompt '请从隔离副本的托盘菜单选择退出，完成后按回车：' || return 7
  fw_phase quit "$since" && fw_https quit --proxy '' --noproxy '*' || return 10
  FW_RESULT=PASS
  fw_log 'PASS: 连接和再次连接的代理读回、代理 HTTPS、断开与退出后的配置恢复及直连 HTTPS 均已通过。'
}

fw_main() {
  set -u
  umask 077
  export PATH=/usr/bin:/bin:/usr/sbin:/sbin
  export LC_ALL=C
  FW_ROOT=$(cd "$(/usr/bin/dirname "$0")" && pwd -P) || return 2
  FW_PROBE="$FW_ROOT/FengWoProxyProbe"
  FW_APP="$FW_ROOT/蜂窝授权验证.app"
  FW_EVENTS="$HOME/Library/Application Support/com.fengwo.accelerator.proxytest/diagnostics"
  /bin/mkdir -p "$HOME/Library/Logs/FengWoProxyTest" || return 2
  FW_LOG_DIR=$(/usr/bin/mktemp -d "$HOME/Library/Logs/FengWoProxyTest/run-$(/bin/date '+%Y%m%d-%H%M%S')-XXXXXX") || return 2
  FW_STARTED=$(/bin/date +%s)
  FW_RESULT=NOT_VERIFIED
  trap fw_finalize EXIT
  trap 'exit 130' INT TERM
  [ "$#" -le 1 ] || return 2
  fw_run "${1:-interactive}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  fw_main "$@"
  exit $?
fi
