#!/usr/bin/env bash
# =============================================================================
# 02_tftp_flash.sh — Preparacion del TFTP recovery de U-Boot
# =============================================================================
# Deja la notebook y el servidor TFTP listos para que el TL-MR3420 descargue
# tp_recovery.bin al entrar en modo recovery. NO flashea por si solo: el
# arranque en recovery requiere la accion fisica del usuario.
#
# Que hace:
#   1. Verifica que firmware/tp_recovery.bin exista y tenga el SHA256 correcto.
#   2. Crea/actualiza el perfil NetworkManager "mr3420-tftp" con IP estatica
#      192.168.0.225/24 en la interfaz cableada, sin gateway ni DNS.
#   3. Desactiva el perfil temporal DHCP y activa "mr3420-tftp".
#   4. Arranca dnsmasq como servidor TFTP (solo en esa interfaz/IP).
#   5. Verifica proceso, puerto UDP/69 y legibilidad de la imagen.
#
# Uso:
#   ./scripts/02_tftp_flash.sh
#
# Despues de ejecutarlo, seguir las instrucciones fisicas impresas al final.
# Para detener el TFTP y restaurar la red: ./scripts/99_restore_network.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROYECTO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROYECTO_DIR}/config"
FIRMWARE_DIR="${PROYECTO_DIR}/firmware"
TFTP_LOG="/tmp/mr3420-tftp.log"
TFTP_PIDFILE="/tmp/mr3420-tftp.pid"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: no existe ${CONFIG_FILE}." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

RECOVERY_FILE="${FIRMWARE_DIR}/${TFTP_FILENAME}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# --- 0. Comprobaciones de herramientas y permisos ----------------------------
for cmd in nmcli dnsmasq sha256sum pgrep ss sudo; do
  command -v "${cmd}" >/dev/null 2>&1 || die "falta la herramienta: ${cmd}"
done
sudo -n true || die "se requieren privilegios sudo sin password para dnsmasq"

# --- 1. Verificar imagen -----------------------------------------------------
[[ -f "${RECOVERY_FILE}" ]] || die "no existe ${RECOVERY_FILE}. Ejecutar 01_download_firmware.sh"
ACTUAL_SHA="$(sha256sum "${RECOVERY_FILE}" | awk '{print $1}')"
[[ "${ACTUAL_SHA}" == "${FIRMWARE_SHA256}" ]] || die "SHA256 incorrecto en ${RECOVERY_FILE}"
[[ -s "${RECOVERY_FILE}" ]] || die "${RECOVERY_FILE} esta vacio"
log "Imagen verificada: ${RECOVERY_FILE} ($(stat -c %s "${RECOVERY_FILE}") bytes)"

# --- 2. Perfil NetworkManager estatico ---------------------------------------
if ! ip link show "${NOTEBOOK_IFACE}" >/dev/null 2>&1; then
  die "no existe la interfaz ${NOTEBOOK_IFACE}"
fi

if nmcli -t -f NAME connection show | grep -Fxq "${TEMP_TFTP_PROFILE}"; then
  log "Actualizando perfil NM ${TEMP_TFTP_PROFILE}"
  nmcli connection modify "${TEMP_TFTP_PROFILE}" \
    connection.interface-name "${NOTEBOOK_IFACE}" \
    ipv4.method manual \
    ipv4.addresses "${NOTEBOOK_TFTP_IP}/24" \
    ipv4.gateway "" \
    ipv4.dns "" \
    ipv4.never-default yes \
    ipv6.method disabled \
    connection.autoconnect no
else
  log "Creando perfil NM ${TEMP_TFTP_PROFILE}"
  nmcli connection add type ethernet ifname "${NOTEBOOK_IFACE}" \
    con-name "${TEMP_TFTP_PROFILE}" \
    ipv4.method manual \
    ipv4.addresses "${NOTEBOOK_TFTP_IP}/24" \
    ipv4.gateway "" \
    ipv4.dns "" \
    ipv4.never-default yes \
    ipv6.method disabled \
    connection.autoconnect no
fi

# --- 3. Activar el perfil TFTP y desactivar el DHCP temporal -----------------
if nmcli -t -f NAME,DEVICE connection show --active | grep -Fxq "${TEMP_DISC_PROFILE}:${NOTEBOOK_IFACE}"; then
  log "Desactivando perfil ${TEMP_DISC_PROFILE}"
  nmcli connection down "${TEMP_DISC_PROFILE}" || true
fi

log "Activando perfil ${TEMP_TFTP_PROFILE}"
nmcli connection up "${TEMP_TFTP_PROFILE}" || die "no se pudo activar ${TEMP_TFTP_PROFILE}"

# Verificar IP asignada
for _ in $(seq 1 10); do
  ip -4 addr show dev "${NOTEBOOK_IFACE}" | grep -q "inet ${NOTEBOOK_TFTP_IP}/24" && break
  sleep 0.5
done
ip -4 addr show dev "${NOTEBOOK_IFACE}" | grep -q "inet ${NOTEBOOK_TFTP_IP}/24" \
  || die "la interfaz ${NOTEBOOK_IFACE} no tiene ${NOTEBOOK_TFTP_IP}/24"
log "IP de la notebook: $(ip -4 -o addr show dev "${NOTEBOOK_IFACE}" | awk '{print $4}')"

# --- 4. Servidor TFTP --------------------------------------------------------
# Detener una instancia previa de este proyecto, si existe.
if [[ -f "${TFTP_PIDFILE}" ]]; then
  OLD_PID="$(cat "${TFTP_PIDFILE}" 2>/dev/null || true)"
  if [[ -n "${OLD_PID}" ]] && ps -p "${OLD_PID}" >/dev/null 2>&1; then
    log "Deteniendo dnsmasq previo (PID ${OLD_PID})"
    sudo -n kill "${OLD_PID}" 2>/dev/null || true
    sleep 0.5
  fi
  sudo -n rm -f "${TFTP_PIDFILE}"
fi

sudo -n rm -f "${TFTP_LOG}"
log "Arrancando dnsmasq TFTP en ${NOTEBOOK_TFTP_IP}:69 (raiz ${FIRMWARE_DIR})"
sudo -n dnsmasq \
  --port=0 \
  --interface="${NOTEBOOK_IFACE}" \
  --bind-interfaces \
  --listen-address="${NOTEBOOK_TFTP_IP}" \
  --enable-tftp \
  --tftp-root="${FIRMWARE_DIR}" \
  --tftp-no-blocksize \
  --user=root \
  --log-facility="${TFTP_LOG}" \
  --pid-file="${TFTP_PIDFILE}"

# --- 5. Verificaciones -------------------------------------------------------
sleep 1
TFTP_PID="$(cat "${TFTP_PIDFILE}" 2>/dev/null || true)"
if [[ -z "${TFTP_PID}" ]] || ! ps -p "${TFTP_PID}" >/dev/null 2>&1; then
  sudo -n tail -n 30 "${TFTP_LOG}" 2>/dev/null || true
  die "dnsmasq no quedo corriendo"
fi
log "dnsmasq activo: PID ${TFTP_PID}"

if ! sudo -n ss -lunp | grep -q ':69 '; then
  sudo -n tail -n 30 "${TFTP_LOG}" 2>/dev/null || true
  die "dnsmasq no escucha en UDP/69"
fi
log "Escuchando en UDP/69: $(sudo -n ss -lunp | grep ':69 ' | tr -s ' ')"

if ! sudo -n test -r "${RECOVERY_FILE}"; then
  die "${RECOVERY_FILE} no es legible por root"
fi
log "Imagen accesible por TFTP: ${TFTP_FILENAME}"

log "Log TFTP: ${TFTP_LOG}"
sudo -n tail -n 15 "${TFTP_LOG}" 2>/dev/null || true

cat <<EOF

=============================================================================
 READY_FOR_POWER_CYCLE
=============================================================================
La notebook esta lista en ${NOTEBOOK_TFTP_IP}/24 y dnsmasq sirve
${TFTP_FILENAME} desde ${FIRMWARE_DIR}.

Accion fisica requerida (la realiza el usuario):
  1. Apagar el TL-MR3420 (desconectar la alimentacion).
  2. Verificar que el cable Ethernet siga en un puerto LAN (no WAN).
  3. Mantener pulsado el boton Reset/WPS.
  4. Encender el router sin soltar Reset.
  5. Sostener 6-7 segundos, hasta ver actividad TFTP en el log.
  6. Soltar Reset.
  7. NO cortar la alimentacion durante la escritura ni el primer arranque.

Monitoreo en otra terminal:
  sudo -n tail -f ${TFTP_LOG}

Al terminar, restaurar la red de la notebook:
  ${SCRIPT_DIR}/99_restore_network.sh
=============================================================================
EOF
