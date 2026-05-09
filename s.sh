#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash s.sh "SSID" "PASSWORD" [IFACE]
# Example:
#   bash s.sh "MyWiFi" "MyPass123" "wlp0s20f3"

SSID="${1:-}"
PASS="${2:-}"
IFACE="${3:-wlp0s20f3}"

if [[ -z "$SSID" || -z "$PASS" ]]; then
  echo "Usage: $0 \"SSID\" \"PASSWORD\" [IFACE]"
  exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root: sudo bash $0 \"SSID\" \"PASSWORD\" [IFACE]"
  exit 1
fi

echo "[1/7] Detecting Debian codename..."
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-trixie}")"
if [[ -z "$CODENAME" ]]; then
  CODENAME="trixie"
fi
echo "Codename: $CODENAME"

# Ceph repo path for PVE 9 (trixie). For other codenames keep squid by default.
CEPH_REPO_PATH="ceph-squid"

echo "[2/7] Disabling enterprise repositories (if present)..."
for f in /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/ceph.list; do
  if [[ -f "$f" ]]; then
    cp -a "$f" "${f}.bak.$(date +%s)"
    sed -i 's/^[[:space:]]*deb[[:space:]]/# deb /' "$f"
  fi
done

echo "[3/7] Adding no-subscription repositories..."
cat > /etc/apt/sources.list.d/pve-no-subscription.list <<EOF
deb http://download.proxmox.com/debian/pve ${CODENAME} pve-no-subscription
EOF

cat > /etc/apt/sources.list.d/ceph-no-subscription.list <<EOF
deb http://download.proxmox.com/debian/${CEPH_REPO_PATH} ${CODENAME} no-subscription
EOF

echo "[4/7] Installing Wi-Fi tools..."
apt update
apt install -y wpasupplicant iw wireless-tools isc-dhcp-client

echo "[5/7] Preparing Wi-Fi interface ${IFACE}..."
ip link set "${IFACE}" up

mkdir -p /etc/wpa_supplicant
wpa_passphrase "$SSID" "$PASS" > /etc/wpa_supplicant/wpa_supplicant.conf
chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf

# Stop old wpa_supplicant for this iface, if running
pkill -f "wpa_supplicant.*${IFACE}" || true
sleep 1

# Start fresh
if command -v wpa_supplicant >/dev/null 2>&1; then
  wpa_supplicant -B -i "${IFACE}" -c /etc/wpa_supplicant/wpa_supplicant.conf
else
  /usr/sbin/wpa_supplicant -B -i "${IFACE}" -c /etc/wpa_supplicant/wpa_supplicant.conf
fi

echo "[6/7] Requesting DHCP lease..."
dhclient -r "${IFACE}" || true
dhclient "${IFACE}"

echo "[7/7] Making it persistent in /etc/network/interfaces..."
if ! grep -q "BEGIN PROXMOX WIFI ${IFACE}" /etc/network/interfaces; then
  cp -a /etc/network/interfaces "/etc/network/interfaces.bak.$(date +%s)"
  cat >> /etc/network/interfaces <<EOF

# BEGIN PROXMOX WIFI ${IFACE}
auto ${IFACE}
iface ${IFACE} inet dhcp
    wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
# END PROXMOX WIFI ${IFACE}
EOF
fi

echo
echo "=== DONE ==="
ip -4 a show "${IFACE}" || true
ip r || true
echo
echo "Check internet:"
echo "  ping -c 4 8.8.8.8"
