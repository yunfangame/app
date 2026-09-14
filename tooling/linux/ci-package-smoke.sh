#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${GITHUB_ACTIONS:-} == true && $(uname -s) == Linux && $(id -u) != 0 ]]
mapfile -t packages < <(find dist -maxdepth 1 -type f -name '*.deb')
[[ ${#packages[@]} == 1 ]]
package=$(realpath "${packages[0]}")
package_name=$(dpkg-deb -f "$package" Package)
mkdir -p smoke-evidence
sudo apt-get install -y xvfb xauth openbox xdotool scrot "$package"
app=$(dpkg-query -L "$package_name" | awk '/\/FlClash$/ {print; exit}')
[[ -x $app ]]
helper="$(dirname "$app")/FlClashHelperService"
[[ -x $helper ]]

cleanup() {
  sudo "$helper" uninstall || true
  sudo apt-get remove -y "$package_name" || true
}
trap cleanup EXIT
sudo env PKEXEC_UID="$(id -u)" "$helper" install
systemctl is-active --quiet flclash-helper.service
python3 tooling/linux/ci-helper-smoke.py "$(dirname "$app")"
sudo "$helper" uninstall
if systemctl is-active --quiet flclash-helper.service; then
  exit 1
fi
xvfb-run -a -s '-screen 0 1440x1000x24' dbus-run-session -- \
  bash tooling/linux/ci-desktop-smoke.sh "$app" "$PWD/smoke-evidence"
sudo apt-get install --reinstall -y "$package"
test -x "$app"
sudo env PKEXEC_UID="$(id -u)" "$helper" install
sudo apt-get remove -y "$package_name"
test ! -e /etc/systemd/system/flclash-helper.service
if systemctl is-active --quiet flclash-helper.service; then
  exit 1
fi
trap - EXIT
printf '%s\n' 'Ubuntu package install, reinstall, removal and Helper smoke passed.'
