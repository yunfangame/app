#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${GITHUB_ACTIONS:-} == true && $(id -u) == 0 && -e /.dockerenv ]]
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates dbus-x11 xvfb xauth openbox xdotool scrot /work/dist/*.deb
package=$(find /work/dist -maxdepth 1 -name '*.deb' -print -quit)
package_name=$(dpkg-deb -f "$package" Package)
app=$(dpkg-query -L "$package_name" | awk '/\/FlClash\/FlClash$/ {print; exit}')
[[ -x $app ]]
ldd "$app" | tee /evidence/linked-libraries.txt
if grep -q 'not found' /evidence/linked-libraries.txt; then
  exit 1
fi
useradd -m smoke
runuser -u smoke -- env GITHUB_ACTIONS=true \
  xvfb-run -a -s '-screen 0 1440x1000x24' dbus-run-session -- \
  bash /work/tooling/linux/ci-desktop-smoke.sh "$app" /evidence
apt-get remove -y "$package_name"
test ! -e "$app"
test ! -e /etc/systemd/system/flclash-helper.service
printf '%s\n' 'Debian 12 package dependencies, launch, relaunch and removal passed.'
