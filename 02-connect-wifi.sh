#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash 02-connect-wifi.sh "SSID" "PASSWORD" [IFACE]
# Example:
#   bash 02-connect-wifi.sh "MyWiFi" "MyPass123" "wlp0s20f3"

SSID="${1:-}"
PASS="${2:-}"
IFACE="${3:-wlp0s20f3}"

if [[ -z "$SSID" || -z "$PASS" ]]; then
  echo "Usage: $0 \"SSID\" \"PASSWORD\" [IFACE]"
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0 \"SSID\" \"PASSWORD\" [IFACE]"
  exit 1
fi

if ! command -v wpa_passphrase >/dev/null 2>&1; then
  echo "wpa_passphrase not found. Run 01-fix-proxmox-repos.sh first."
  exit 1
fi

WPA_BIN="$(command -v wpa_supplicant || true)"
if [[ -z "${WPA_BIN}" && -x /usr/sbin/wpa_supplicant ]]; then
  WPA_BIN="/usr/sbin/wpa_supplicant"
fi
if [[ -z "${WPA_BIN}" && -x /sbin/wpa_supplicant ]]; then
  WPA_BIN="/sbin/wpa_supplicant"
fi
if [[ -z "${WPA_BIN}" ]]; then
  echo "wpa_supplicant binary not found. Run 01-fix-proxmox-repos.sh first."
  exit 1
fi

echo "[1/6] Bringing interface up: ${IFACE}"
ip link set "${IFACE}" up

echo "[2/6] Writing /etc/wpa_supplicant/wpa_supplicant.conf"
mkdir -p /etc/wpa_supplicant
wpa_passphrase "${SSID}" "${PASS}" > /etc/wpa_supplicant/wpa_supplicant.conf
chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf

echo "[3/6] Restarting wpa_supplicant on ${IFACE}"
pkill -f "wpa_supplicant.*${IFACE}" || true
sleep 1
"${WPA_BIN}" -B -i "${IFACE}" -c /etc/wpa_supplicant/wpa_supplicant.conf

echo "[4/6] Requesting DHCP lease on ${IFACE}"
dhclient -r "${IFACE}" || true
dhclient "${IFACE}"

echo "[5/6] Persisting config in /etc/network/interfaces"
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

echo "[6/6] Status"
ip -4 a show "${IFACE}" || true
ip r || true
echo
echo "Check connectivity:"
echo "  ping -c 4 8.8.8.8"
