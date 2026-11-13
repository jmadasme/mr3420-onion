#!/usr/bin/env bash
# =============================================================================
# 03_ssh_setup.sh — Acceso SSH, contrasena root y hardening basico
# =============================================================================
# Se ejecuta DESPUES del TFTP recovery, cuando OpenWrt ya responde en su LAN.
#
# Que hace:
#   1. Asegura conectividad con el router (activa el perfil DHCP temporal si
#      hace falta; el perfil TFTP deja de ser util tras el flasheo).
#   2. Entra por SSH con la contrasena de config o, en el primer arranque de
#      OpenWrt, con contrasena vacia.
#   3. Define la contrasena root de config (passwd).
#   4. Configura hostname, firewall (WAN cerrada, LAN abierta) y verifica
#      Internet/espacio/arquitectura.
#   5. Opcionalmente cambia la LAN a otra subred para evitar colision con la
#      WAN de Starlink (192.168.1.0/24). Ver --lan-ip.
#
# Uso:
#   ./scripts/03_ssh_setup.sh [--lan-ip 192.168.10.1] [--wait 180] [--fix-collision]
#
# Opciones:
#   --lan-ip IP        Cambia la LAN del router a IP/24 (p.ej. 192.168.10.1)
#                      y actualiza ROUTER_IP en config. Recomendado si la WAN
#                      de Starlink usa 192.168.1.0/24.
#   --fix-collision    Detecta WAN en 192.168.1.0/24 y cambia la LAN a
#                      192.168.10.1 automaticamente.
#   --wait SEGUNDOS    Espera maxima a que el router responda (default 180).
#
# No instala nada en la notebook. No toca Tor ni uhttpd.
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

WAIT_SECONDS=180
LAN_IP_OVERRIDE=""
FIX_COLLISION=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lan-ip)         LAN_IP_OVERRIDE="${2:?falta IP}"; shift 2 ;;
    --fix-collision)  FIX_COLLISION=1; shift ;;
    --wait)           WAIT_SECONDS="${2:?falta segundos}"; shift 2 ;;
    -h|--help)        sed -n '2,40p' "$0"; exit 0 ;;
    *)                echo "ERROR: opcion desconocida: $1" >&2; exit 1 ;;
  esac
done

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

for cmd in ssh sshpass nc ping nmcli; do
  command -v "${cmd}" >/dev/null 2>&1 || die "falta la herramienta: ${cmd}"
done
mkdir -p "$(dirname "${KNOWN_HOSTS}")"
touch "${KNOWN_HOSTS}"

SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="${KNOWN_HOSTS}"
  -o ConnectTimeout=10
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=3
)

ssh_pw() {
  local password="$1"; shift
  sshpass -p "${password}" ssh "${SSH_OPTS[@]}" "${ROUTER_USER}@${ROUTER_IP}" "$@"
}

ssh_new() { ssh_pw "${ROOT_PASSWORD}" "$@"; }

wait_for_tcp() {
  local host="$1" port="$2" seconds="$3" i
  for ((i = 0; i < seconds; i++)); do
    if nc -z -w 2 "${host}" "${port}" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# --- 1. Conectividad con el router ------------------------------------------
if ! ping -c 1 -W 2 "${ROUTER_IP}" >/dev/null 2>&1; then
  log "Router no alcanzable en ${ROUTER_IP}; activando perfil DHCP ${TEMP_DISC_PROFILE}"
  if ! nmcli -t -f NAME connection show | grep -Fxq "${TEMP_DISC_PROFILE}"; then
    nmcli connection add type ethernet ifname "${NOTEBOOK_IFACE}" \
      con-name "${TEMP_DISC_PROFILE}" ipv4.method auto connection.autoconnect yes
  fi
  nmcli connection down "${TEMP_TFTP_PROFILE}" 2>/dev/null || true
  nmcli connection up "${TEMP_DISC_PROFILE}" || die "no se pudo activar ${TEMP_DISC_PROFILE}"
fi

log "Esperando SSH en ${ROUTER_IP}:22 (max ${WAIT_SECONDS}s)"
wait_for_tcp "${ROUTER_IP}" 22 "${WAIT_SECONDS}" || die "SSH no responde en ${ROUTER_IP}"

# --- 2. Autenticacion --------------------------------------------------------
CURRENT_PW=""
if ssh_pw "${ROOT_PASSWORD}" true >/dev/null 2>&1; then
  CURRENT_PW="${ROOT_PASSWORD}"
  log "Login SSH con la contrasena de config"
elif ssh_pw "" true >/dev/null 2>&1; then
  CURRENT_PW=""
  log "Login SSH con contrasena vacia (primer arranque de OpenWrt)"
else
  die "no se pudo autenticar por SSH como ${ROUTER_USER}@${ROUTER_IP}"
fi

if [[ -z "${CURRENT_PW}" ]]; then
  log "Definiendo contrasena root"
  if ! printf '%s\n%s\n' "${ROOT_PASSWORD}" "${ROOT_PASSWORD}" | \
       sshpass -p "" ssh -tt "${SSH_OPTS[@]}" "${ROUTER_USER}@${ROUTER_IP}" 'passwd root'; then
    die "fallo passwd root"
  fi
  sleep 1
  ssh_pw "${ROOT_PASSWORD}" true >/dev/null 2>&1 \
    || die "la nueva contrasena root no funciona"
  log "Contrasena root definida y verificada"
else
  log "La contrasena root ya estaba definida"
fi

# --- 3. Hardening y datos del sistema ---------------------------------------
log "Configurando hostname"
ssh_new "uci set system.@system[0].hostname='mr3420-onion'; uci commit system" \
  || die "fallo al configurar hostname"

log "Aplicando firewall (WAN cerrada, LAN abierta)"
ssh_new "
  uci set firewall.@zone[1].input='REJECT'
  uci set firewall.@zone[1].forward='REJECT'
  uci set firewall.@zone[1].masq='1'
  uci set firewall.@zone[0].input='ACCEPT'
  uci commit firewall
  /etc/init.d/firewall reload >/dev/null 2>&1 || true
" || die "fallo al aplicar firewall"

log "Descubrimiento del sistema"
ssh_new "uname -m; cat /etc/openwrt_release; df -h /overlay; free; opkg --version 2>/dev/null | head -n1"

# --- 4. Internet y deteccion de colision ------------------------------------
WAN_IP="$(ssh_new "ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@.ipv4-address[0].address' 2>/dev/null" || true)"
if [[ -n "${WAN_IP}" ]]; then
  log "IP WAN actual: ${WAN_IP}"
else
  log "WAN sin IP (cable Starlink no conectado o sin DHCP todavia)"
fi

if ssh_new "ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1"; then
  log "Internet IPv4: OK (ping 1.1.1.1)"
else
  log "ADVERTENCIA: sin ping a 1.1.1.1 (revisar cable WAN/DHCP antes de Tor)"
fi
if ssh_new "nslookup openwrt.org >/dev/null 2>&1"; then
  log "DNS: OK (nslookup openwrt.org)"
else
  log "ADVERTENCIA: DNS no resuelve (Tor no podra bootstrapear)"
fi

LAN_CHANGE=""
if [[ -n "${LAN_IP_OVERRIDE}" ]]; then
  LAN_CHANGE="${LAN_IP_OVERRIDE}"
elif [[ "${FIX_COLLISION}" -eq 1 && "${WAN_IP}" == 192.168.1.* && "${ROUTER_IP}" == "192.168.1.1" ]]; then
  LAN_CHANGE="192.168.10.1"
fi

if [[ -n "${LAN_CHANGE}" ]]; then
  [[ "${LAN_CHANGE}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "IP de LAN invalida: ${LAN_CHANGE}"
  log "Cambiando LAN del router a ${LAN_CHANGE}/24 (evita colision con Starlink)"
  ssh_new "uci set network.lan.ipaddr='${LAN_CHANGE}'; uci commit network; /etc/init.d/network reload >/dev/null 2>&1" || true
  sed -i "s/^ROUTER_IP=.*/ROUTER_IP=${LAN_CHANGE}/" "${CONFIG_FILE}"
  ROUTER_IP="${LAN_CHANGE}"
  log "Renovando DHCP de la notebook"
  nmcli connection down "${TEMP_DISC_PROFILE}" 2>/dev/null || true
  sleep 2
  nmcli connection up "${TEMP_DISC_PROFILE}" 2>/dev/null || true
  log "Esperando SSH en la nueva IP ${ROUTER_IP} (max 120s)"
  if ! wait_for_tcp "${ROUTER_IP}" 22 120; then
    die "el router no responde en ${ROUTER_IP} tras cambiar la LAN; revisar conexion"
  fi
  ssh_new "true" >/dev/null 2>&1 || die "SSH no autentica en la nueva IP ${ROUTER_IP}"
  log "LAN cambiada y SSH revalidado en ${ROUTER_IP}"
fi

# --- 5. Resumen --------------------------------------------------------------
log "SSH: ${ROUTER_USER}@${ROUTER_IP} (contrasena en config, no se imprime)"
log "Hostname: $(ssh_new 'cat /proc/sys/kernel/hostname')"
log "Firmware: $(ssh_new '. /etc/openwrt_release; echo ${DISTRIB_ID} ${DISTRIB_RELEASE}')"
log "Overlay libre: $(ssh_new "df -h /overlay | awk 'NR==2 {print \$4}'")"
log "Listo para instalar Tor: ./scripts/04_install_tor.sh"
