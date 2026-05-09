#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash wifi-connect.sh "SSID" "PASSWORD" [IFACE]
# Example:
#   bash wifi-connect.sh "MyWiFi" "MyPass123" "wlp0s20f3"

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

if ! command -v wpa_passphrase >/dev/null 2>&1; then
  echo "Error: wpa_passphrase not found (install wpasupplicant)."
  exit 1
fi

WPA_BIN="$(command -v wpa_supplicant || true)"
if [[ -z "$WPA_BIN" && -x /usr/sbin/wpa_supplicant ]]; then WPA_BIN="/usr/sbin/wpa_supplicant"; fi
if [[ -z "$WPA_BIN" && -x /sbin/wpa_supplicant ]]; then WPA_BIN="/sbin/wpa_supplicant"; fi
if [[ -z "$WPA_BIN" ]]; then
  echo "Error: wpa_supplicant not found."
  exit 1
fi

echo "[1/5] Interface up: $IFACE"
ip link set "$IFACE" up

echo "[2/5] Create Wi-Fi config"
mkdir -p /etc/wpa_supplicant
wpa_passphrase "$SSID" "$PASS" > /etc/wpa_supplicant/wpa_supplicant.conf
chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf

echo "[3/5] Restart wpa_supplicant"
pkill -f "wpa_supplicant.*$IFACE" || true
sleep 1
"$WPA_BIN" -B -i "$IFACE" -c /etc/wpa_supplicant/wpa_supplicant.conf

echo "[4/5] Request DHCP"
dhclient -r "$IFACE" || true
dhclient "$IFACE"

echo "[5/5] Result"
ip -4 a show "$IFACE" || true
ip r || true
echo "Test: ping -c 4 8.8.8.8"
