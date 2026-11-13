#!/usr/bin/env bash
# =============================================================================
# 06_wifi_ap.sh — Wi-Fi AP de gestion (SSID + WPA2)
# =============================================================================
# Configura el radio 2.4 GHz del TL-MR3420 como punto de acceso de la LAN,
# con el SSID y la clave definidos en config (WIFI_SSID / WIFI_KEY).
#
# Uso:
#   ./scripts/06_wifi_ap.sh
#
# La clave WPA2 se genera en la FASE A y vive solo en config (chmod 600,
# gitignored). No se imprime en logs.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROYECTO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROYECTO_DIR}/config"
KNOWN_HOSTS="${PROYECTO_DIR}/.ssh_known_hosts"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: no existe ${CONFIG_FILE}." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

command -v ssh >/dev/null 2>&1 || die "falta ssh"
command -v sshpass >/dev/null 2>&1 || die "falta sshpass"
mkdir -p "$(dirname "${KNOWN_HOSTS}")"
touch "${KNOWN_HOSTS}"

SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="${KNOWN_HOSTS}"
  -o ConnectTimeout=10
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=3
)
router_ssh() {
  sshpass -p "${ROOT_PASSWORD}" ssh "${SSH_OPTS[@]}" "${ROUTER_USER}@${ROUTER_IP}" "$@"
}

router_ssh "true" >/dev/null 2>&1 || die "sin SSH en ${ROUTER_IP}; ejecutar 03_ssh_setup.sh"

# --- 1. Detectar radio -------------------------------------------------------
RADIO="$(router_ssh "uci show wireless 2>/dev/null | sed -n \"s/^wireless\.\\(radio[0-9]*\\)\.type=.*/\\1/p\" | head -n1")"
[[ -n "${RADIO}" ]] || die "no se detecto ningun radio en /etc/config/wireless"
IFACE="default_${RADIO}"
log "Radio detectado: ${RADIO} (seccion ${IFACE})"

# --- 2. Configurar AP --------------------------------------------------------
log "Configurando AP '${WIFI_SSID}' (WPA2-PSK)"
router_ssh "
  set -e
  uci set wireless.${RADIO}.disabled='0'
  uci set wireless.${IFACE}=wifi-iface
  uci set wireless.${IFACE}.device='${RADIO}'
  uci set wireless.${IFACE}.network='lan'
  uci set wireless.${IFACE}.mode='ap'
  uci set wireless.${IFACE}.ssid='${WIFI_SSID}'
  uci set wireless.${IFACE}.encryption='psk2'
  uci set wireless.${IFACE}.key='${WIFI_KEY}'
  uci set wireless.${IFACE}.disabled='0'
  uci commit wireless
" || die "fallo la configuracion UCI de wireless"

log "Recargando Wi-Fi"
router_ssh "wifi reload" || die "fallo wifi reload"
sleep 4

# --- 3. Verificar ------------------------------------------------------------
SSID_ACTUAL="$(router_ssh "uci -q get wireless.${IFACE}.ssid")"
[[ "${SSID_ACTUAL}" == "${WIFI_SSID}" ]] || die "el SSID configurado no coincide"
log "SSID configurado: ${SSID_ACTUAL}"

if router_ssh "command -v iwinfo >/dev/null 2>&1"; then
  router_ssh "iwinfo 2>/dev/null | head -n 10" || true
  router_ssh "iwinfo ${RADIO} info 2>/dev/null || true" || true
fi

log "Estado wireless (ubus):"
router_ssh "ubus call network.wireless status 2>/dev/null | grep -E '\"ssid\"|\"up\"|\"disabled\"' | head -n 12" || true

log "Wi-Fi AP configurado. Clave en config (WIFI_KEY), no se imprime."
log "Listo. Siguiente: ./scripts/07_verify.sh"
