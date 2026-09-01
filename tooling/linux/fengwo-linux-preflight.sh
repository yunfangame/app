#!/usr/bin/env bash

set -Eeuo pipefail

original_args=("$@")
check_only=0
package_path=''
config_url='https://house.zryc.tech/ConFigOss4.json'
warning_count=0
error_count=0
repair_count=0
apt_updated=0

usage() {
  printf '%s\n' \
    '蜂窝加速器 Linux 安装预检' \
    '' \
    '用法：' \
    '  sudo ./fengwo-linux-preflight.sh [--package 安装包.deb]' \
    '  ./fengwo-linux-preflight.sh --check-only' \
    '' \
    '选项：' \
    '  --package PATH      预检通过后安装 DEB 或 RPM 包' \
    '  --config-url URL    指定远程配置连通性检测地址' \
    '  --check-only        只检查，不安装依赖、不修改失效代理' \
    '  -h, --help          显示帮助'
}

pass() {
  printf '[通过] %s\n' "$*"
}

warn() {
  warning_count=$((warning_count + 1))
  printf '[提醒] %s\n' "$*" >&2
}

fail() {
  error_count=$((error_count + 1))
  printf '[失败] %s\n' "$*" >&2
}

repaired() {
  repair_count=$((repair_count + 1))
  printf '[已修复] %s\n' "$*"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

while (($# > 0)); do
  case "$1" in
    --package)
      [[ $# -ge 2 ]] || {
        printf '缺少 --package 参数\n' >&2
        exit 2
      }
      package_path=$2
      shift 2
      ;;
    --config-url)
      [[ $# -ge 2 ]] || {
        printf '缺少 --config-url 参数\n' >&2
        exit 2
      }
      config_url=$2
      shift 2
      ;;
    --check-only)
      check_only=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '未知参数：%s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ $(uname -s) != 'Linux' ]]; then
  printf '此脚本仅支持 Linux。\n' >&2
  exit 1
fi

if ((check_only == 0 && EUID != 0)); then
  if command_exists sudo; then
    exec sudo -- "$0" "${original_args[@]}"
  fi
  printf '自动修复和安装需要 root 权限，请使用 sudo 运行。\n' >&2
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  ID='unknown'
  ID_LIKE=''
  PRETTY_NAME='未知 Linux'
fi

case " ${ID:-} ${ID_LIKE:-} " in
  *debian*|*ubuntu*) package_family='debian' ;;
  *fedora*|*rhel*|*centos*) package_family='rpm' ;;
  *) package_family='unknown' ;;
esac

printf '系统：%s\n' "${PRETTY_NAME:-Linux}"
printf '架构：%s\n' "$(uname -m)"
printf '模式：%s\n' "$([[ $check_only == 1 ]] && printf '只检查' || printf '自动修复')"

if [[ $package_family == 'unknown' ]]; then
  fail '当前发行版不在自动修复支持范围内，仅支持 Debian/Ubuntu 和 Fedora/RHEL 系。'
fi

ensure_apt_updated() {
  if ((apt_updated == 1)); then
    return
  fi
  if DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get update; then
    apt_updated=1
  else
    fail '软件源更新失败。'
  fi
}

ensure_debian_packages() {
  local missing=()
  local package
  for package in "$@"; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q '^install ok installed$'; then
      missing+=("$package")
    fi
  done
  if ((${#missing[@]} == 0)); then
    pass '运行依赖完整。'
    return
  fi
  if ((check_only == 1)); then
    warn "缺少运行依赖：${missing[*]}"
    return
  fi
  ensure_apt_updated
  if ((error_count > 0)); then
    return
  fi
  if DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y "${missing[@]}"; then
    repaired "已安装运行依赖：${missing[*]}"
  else
    fail "运行依赖安装失败：${missing[*]}"
  fi
}

ensure_rpm_packages() {
  local missing=()
  local package
  for package in "$@"; do
    if ! rpm -q "$package" >/dev/null 2>&1; then
      missing+=("$package")
    fi
  done
  if ((${#missing[@]} == 0)); then
    pass '运行依赖完整。'
    return
  fi
  if ((check_only == 1)); then
    warn "缺少运行依赖：${missing[*]}"
    return
  fi
  if command_exists dnf && dnf install -y "${missing[@]}"; then
    repaired "已安装运行依赖：${missing[*]}"
  else
    fail "运行依赖安装失败：${missing[*]}"
  fi
}

if [[ $package_family == 'debian' ]]; then
  ensure_debian_packages \
    ca-certificates \
    curl \
    dbus-user-session \
    fontconfig \
    fonts-noto-cjk \
    gnome-keyring \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    libayatana-appindicator3-1 \
    libglib2.0-bin \
    libkeybinder-3.0-0 \
    libsecret-1-0 \
    xdg-utils
elif [[ $package_family == 'rpm' ]]; then
  ensure_rpm_packages \
    ca-certificates \
    curl \
    dbus-daemon \
    fontconfig \
    google-noto-sans-cjk-fonts \
    gnome-keyring \
    glib2 \
    gstreamer1-plugins-bad-free \
    gstreamer1-plugins-base \
    gstreamer1-plugins-good \
    libayatana-appindicator-gtk3 \
    libsecret \
    xdg-utils
fi

if command_exists fc-cache; then
  if ((check_only == 0)); then
    fc-cache -f >/dev/null
    repaired '中文字体缓存已刷新。'
  elif fc-list ':lang=zh' 2>/dev/null | grep -q .; then
    pass '中文字体可用。'
  else
    warn '未检测到中文字体。'
  fi
fi

if [[ -c /dev/net/tun ]]; then
  pass 'TUN 虚拟网卡设备可用。'
else
  if ((check_only == 0)) && command_exists modprobe && modprobe tun 2>/dev/null && [[ -c /dev/net/tun ]]; then
    repaired 'TUN 内核模块已加载。'
  else
    warn 'TUN 不可用；系统代理模式仍可使用，但虚拟网卡模式不可用。'
  fi
fi

if command_exists ip && ip route show default | grep -q .; then
  default_route=$(ip route show default | head -n 1)
  pass "默认路由存在：$default_route"
else
  fail '未检测到默认路由。'
fi

detect_desktop_user() {
  if [[ -n ${SUDO_USER:-} && ${SUDO_USER:-} != 'root' ]]; then
    printf '%s' "$SUDO_USER"
    return
  fi
  if ((EUID != 0)); then
    id -un
    return
  fi
  if command_exists loginctl; then
    local session uid user rest active type
    while read -r session uid user rest; do
      [[ -n ${session:-} && ${uid:-0} -ge 1000 ]] || continue
      [[ ${user:-} != 'nobody' ]] || continue
      active=$(loginctl show-session "$session" -p Active --value 2>/dev/null || true)
      type=$(loginctl show-session "$session" -p Type --value 2>/dev/null || true)
      if [[ $active == 'yes' && ($type == 'x11' || $type == 'wayland') ]]; then
        printf '%s' "$user"
        return
      fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
  fi
}

desktop_user=$(detect_desktop_user || true)
run_as_desktop_user() {
  local uid
  uid=$(id -u "$desktop_user")
  if ((EUID == 0)); then
    runuser -u "$desktop_user" -- env \
      XDG_RUNTIME_DIR="/run/user/$uid" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
      "$@"
  else
    env \
      XDG_RUNTIME_DIR="/run/user/$uid" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
      "$@"
  fi
}

port_is_listening() {
  local port=$1
  ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq ":${port}$"
}

repair_stale_proxy() {
  [[ -n $desktop_user ]] || {
    warn '未发现活动图形桌面用户，跳过密钥环和失效代理检查。'
    return
  }
  local uid mode host port local_only=1 listener_found=0
  local hosts=()
  local ports=()
  uid=$(id -u "$desktop_user")
  if [[ ! -S /run/user/$uid/bus ]]; then
    warn "用户 $desktop_user 的 DBus 会话未运行，首次启动时可能出现密钥环提示。"
    return
  fi
  pass "用户 $desktop_user 的 DBus 桌面会话可用。"
  if run_as_desktop_user gdbus call \
    --session \
    --dest org.freedesktop.DBus \
    --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.NameHasOwner org.freedesktop.secrets \
    2>/dev/null | grep -q 'true'; then
    pass 'Secret Service 密钥环服务可用。'
  else
    warn '密钥环服务尚未启动，首次保存账号时会要求创建或解锁密钥环。'
  fi
  command_exists gsettings || return
  mode=$(run_as_desktop_user gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d "'" || true)
  [[ $mode == 'manual' ]] || {
    pass '未发现手动系统代理残留。'
    return
  }
  for scheme in http https socks; do
    host=$(run_as_desktop_user gsettings get "org.gnome.system.proxy.$scheme" host 2>/dev/null | tr -d "'" || true)
    port=$(run_as_desktop_user gsettings get "org.gnome.system.proxy.$scheme" port 2>/dev/null | tr -dc '0-9' || true)
    [[ -z $host ]] || hosts+=("$host")
    [[ -z $port || $port == '0' ]] || ports+=("$port")
  done
  for host in "${hosts[@]}"; do
    if [[ $host != '127.0.0.1' && $host != 'localhost' && $host != '::1' ]]; then
      local_only=0
    fi
  done
  for port in "${ports[@]}"; do
    if port_is_listening "$port"; then
      listener_found=1
    fi
  done
  if ((local_only == 1 && listener_found == 0)) && ! pgrep -x FlClash >/dev/null 2>&1; then
    if ((check_only == 1)); then
      warn '检测到无人监听的本机系统代理残留。'
    elif run_as_desktop_user gsettings set org.gnome.system.proxy mode 'none'; then
      repaired '已清理无人监听的本机系统代理残留。'
    else
      fail '失效代理清理失败。'
    fi
  else
    pass '当前系统代理有监听进程或属于外部代理，保持不变。'
  fi
}

repair_stale_proxy

case "$(uname -m)" in
  x86_64|amd64) host_arch='amd64' ;;
  aarch64|arm64) host_arch='arm64' ;;
  *) host_arch=$(uname -m) ;;
esac

install_package() {
  local absolute package_arch extension
  [[ -f $package_path ]] || {
    fail "安装包不存在：$package_path"
    return
  }
  absolute=$(readlink -f "$package_path")
  extension=${absolute##*.}
  if ((check_only == 0)) && pgrep -x FlClash >/dev/null 2>&1; then
    fail '蜂窝加速器正在运行，请先正常退出客户端再安装。'
    return
  fi
  if [[ $extension == 'deb' ]]; then
    command_exists dpkg-deb || {
      fail '系统缺少 dpkg-deb，无法验证 DEB 安装包。'
      return
    }
    package_arch=$(dpkg-deb -f "$absolute" Architecture 2>/dev/null || true)
    [[ $package_arch == "$host_arch" ]] || {
      fail "安装包架构 $package_arch 与系统架构 $host_arch 不匹配。"
      return
    }
    pass "DEB 安装包架构正确：$package_arch"
    if ((check_only == 0)); then
      if DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y "$absolute"; then
        repaired '蜂窝加速器 DEB 安装完成。'
      else
        fail '蜂窝加速器 DEB 安装失败。'
      fi
    fi
  elif [[ $extension == 'rpm' ]]; then
    command_exists rpm || {
      fail '系统缺少 rpm，无法验证 RPM 安装包。'
      return
    }
    package_arch=$(rpm -qp --qf '%{ARCH}' "$absolute" 2>/dev/null || true)
    [[ ($package_arch == 'x86_64' && $host_arch == 'amd64') || ($package_arch == 'aarch64' && $host_arch == 'arm64') ]] || {
      fail "安装包架构 $package_arch 与系统架构 $host_arch 不匹配。"
      return
    }
    pass "RPM 安装包架构正确：$package_arch"
    if ((check_only == 0)); then
      if command_exists dnf && dnf install -y "$absolute"; then
        repaired '蜂窝加速器 RPM 安装完成。'
      else
        fail '蜂窝加速器 RPM 安装失败。'
      fi
    fi
  else
    fail '仅支持 DEB 或 RPM 安装包。'
  fi
}

if [[ -n $package_path ]]; then
  install_package
fi

find_app_binary() {
  local candidate
  for candidate in \
    /opt/FlClash/FlClash \
    /usr/lib/FlClash/FlClash \
    /usr/local/lib/FlClash/FlClash; do
    if [[ -x $candidate ]]; then
      printf '%s' "$candidate"
      return
    fi
  done
}

app_binary=$(find_app_binary || true)
if [[ -n $app_binary ]]; then
  missing_libraries=$(ldd "$app_binary" 2>/dev/null | grep 'not found' || true)
  if [[ -z $missing_libraries ]]; then
    pass '客户端动态链接库完整。'
  else
    fail "客户端缺少动态链接库：$missing_libraries"
  fi
  core_binary="$(dirname "$app_binary")/FlClashCore"
  if [[ -x $core_binary ]]; then
    pass '代理内核文件存在且可执行。'
  else
    fail '代理内核文件缺失或不可执行。'
  fi
else
  warn '尚未发现已安装的蜂窝加速器客户端。'
fi

if command_exists curl; then
  if curl --fail --silent --show-error \
    --location \
    --max-time 15 \
    --range 0-0 \
    --output /dev/null \
    "$config_url"; then
    pass '远程加密配置地址可访问。'
  else
    fail '远程加密配置地址无法访问，请检查时间、证书或网络。'
  fi
else
  warn '系统没有 curl，跳过远程配置连通性检查。'
fi

printf '\n预检结果：%d 项修复，%d 项提醒，%d 项失败。\n' \
  "$repair_count" \
  "$warning_count" \
  "$error_count"

if ((error_count > 0)); then
  exit 1
fi

printf '系统已满足蜂窝加速器启动条件。\n'
