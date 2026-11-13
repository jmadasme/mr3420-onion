#!/usr/bin/env bash
# =============================================================================
# 99_restore_network.sh — Restaura la red original de la notebook
# =============================================================================
# Detiene el servidor TFTP temporal y devuelve enp0s31f6 al perfil original
# "netplan-enp0s31f6" (192.168.2.3/24, gw 192.168.2.1, DNS 8.8.8.8).
#
# Uso:
#   ./scripts/99_restore_network.sh [--remove-temp]
#
#   --remove-temp   ademas elimina los perfiles temporales mr3420-tftp y
#                   mr3420-disc de NetworkManager.
#
# Seguro de ejecutar aunque no se haya flasheado nada: es idempotente.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROYECTO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROYECTO_DIR}/config"
FIRMWARE_DIR="${PROYECTO_DIR}/firmware"
TFTP_PIDFILE="/tmp/mr3420-tftp.pid"
TFTP_LOG="/tmp/mr3420-tftp.log"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: no existe ${CONFIG_FILE}." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

REMOVE_TEMP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove-temp) REMOVE_TEMP=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "ERROR: opcion desconocida: $1" >&2; exit 1 ;;
  esac
done

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

command -v nmcli >/dev/null 2>&1 || die "falta nmcli"

# --- 1. Detener dnsmasq TFTP -------------------------------------------------
if [[ -f "${TFTP_PIDFILE}" ]]; then
  TFTP_PID="$(cat "${TFTP_PIDFILE}" 2>/dev/null || true)"
  if [[ -n "${TFTP_PID}" ]] && ps -p "${TFTP_PID}" >/dev/null 2>&1; then
    log "Deteniendo dnsmasq TFTP (PID ${TFTP_PID})"
    sudo -n kill "${TFTP_PID}" 2>/dev/null || true
    sleep 1
  fi
  sudo -n rm -f "${TFTP_PIDFILE}"
else
  log "No hay pidfile de dnsmasq; nada que detener"
fi
sudo -n rm -f "${TFTP_LOG}" 2>/dev/null || true

# --- 2. Desactivar perfiles temporales --------------------------------------
for profile in "${TEMP_TFTP_PROFILE}" "${TEMP_DISC_PROFILE}"; do
  if nmcli -t -f NAME connection show | grep -Fxq "${profile}"; then
    log "Desactivando perfil ${profile} (si esta activo)"
    nmcli connection down "${profile}" 2>/dev/null || true
  fi
done

# --- 3. Restaurar perfil original -------------------------------------------
if ! nmcli -t -f NAME connection show | grep -Fxq "${ORIGINAL_NM_PROFILE}"; then
  die "no existe el perfil original ${ORIGINAL_NM_PROFILE}"
fi
log "Activando perfil original ${ORIGINAL_NM_PROFILE}"
nmcli connection up "${ORIGINAL_NM_PROFILE}" || die "no se pudo activar ${ORIGINAL_NM_PROFILE}"

# --- 4. Verificar ------------------------------------------------------------
for _ in $(seq 1 15); do
  ip -4 addr show dev "${NOTEBOOK_IFACE}" | grep -q 'inet 192.168.2.3/24' && break
  sleep 1
done
if ip -4 addr show dev "${NOTEBOOK_IFACE}" | grep -q 'inet 192.168.2.3/24'; then
  log "Red restaurada: $(ip -4 -o addr show dev "${NOTEBOOK_IFACE}" | awk '{print $4}')"
else
  ip -4 addr show dev "${NOTEBOOK_IFACE}" || true
  die "la interfaz no quedo en 192.168.2.3/24"
fi

if [[ "${REMOVE_TEMP}" -eq 1 ]]; then
  for profile in "${TEMP_TFTP_PROFILE}" "${TEMP_DISC_PROFILE}"; do
    if nmcli -t -f NAME connection show | grep -Fxq "${profile}"; then
      log "Eliminando perfil temporal ${profile}"
      nmcli connection delete "${profile}" || true
    fi
  done
fi

log "Red de la notebook restaurada. Fin."
