#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

echo "[1/5] Detecting Debian codename..."
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-trixie}")"
CODENAME="${CODENAME:-trixie}"
echo "Codename: ${CODENAME}"

echo "[2/5] Disabling any enterprise Proxmox repositories..."
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
  [[ -e "$f" ]] || continue
  cp -a "$f" "${f}.bak.$(date +%s)"
  # Comment lines that reference enterprise.proxmox.com
  sed -i -E '/enterprise\.proxmox\.com/s/^[[:space:]]*/# /' "$f"
done

echo "[3/5] Adding no-subscription repositories..."
cat > /etc/apt/sources.list.d/pve-no-subscription.list <<EOF
deb http://download.proxmox.com/debian/pve ${CODENAME} pve-no-subscription
EOF

cat > /etc/apt/sources.list.d/ceph-no-subscription.list <<EOF
deb http://download.proxmox.com/debian/ceph-squid ${CODENAME} no-subscription
EOF

echo "[4/5] Updating package index..."
apt clean
apt update

echo "[5/5] Installing required Wi-Fi tools..."
apt install -y wpasupplicant iw wireless-tools isc-dhcp-client

echo
echo "Done. Enterprise repos disabled and Wi-Fi tools installed."
echo "Quick check:"
echo "  command -v wpa_supplicant && wpa_supplicant -v"
