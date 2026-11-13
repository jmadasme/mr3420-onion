#!/usr/bin/env bash
# =============================================================================
# 04_install_tor.sh — Instalacion de Tor y hidden service v3 persistente
# =============================================================================
# Se ejecuta con el router ya en OpenWrt, con Internet en la WAN y SSH listo.
#
# Que hace:
#   1. Verifica Internet, espacio en /overlay y arquitectura.
#   2. opkg update + opkg install tor (idempotente).
#   3. Crea /etc/tor/hidden_service con permisos 700 y owner tor:tor.
#   4. Escribe /etc/tor/torrc con el mapeo onion:80 -> 127.0.0.1:8080.
#   5. Habilita y reinicia Tor; espera la address .onion y verifica bootstrap.
#   6. Guarda ONION_ADDRESS en config (no versionado).
#
# Uso:
#   ./scripts/04_install_tor.sh [--force]
#
#   --force   continua aunque el espacio libre sea bajo (< 700 KiB).
#
# No configura el servicio local (eso lo hace 05_deploy_uhttpd.sh).
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

FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "ERROR: opcion desconocida: $1" >&2; exit 1 ;;
  esac
done

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

# --- 0. Acceso ---------------------------------------------------------------
router_ssh "true" >/dev/null 2>&1 || die "sin SSH en ${ROUTER_IP}; ejecutar 03_ssh_setup.sh"
log "SSH OK en ${ROUTER_IP}"

# --- 1. Internet -------------------------------------------------------------
if ! router_ssh "ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1"; then
  die "el router no tiene Internet (ping 1.1.1.1). Conectar WAN de Starlink y reintentar"
fi
if ! router_ssh "nslookup openwrt.org >/dev/null 2>&1"; then
  die "el router no resuelve DNS (nslookup openwrt.org). Revisar WAN/DNS antes de Tor"
fi
log "Internet y DNS OK"

# --- 2. Espacio y arquitectura ----------------------------------------------
ARCH="$(router_ssh "uname -m")"
AVAIL_KB="$(router_ssh "df -k /overlay | awk 'NR==2 {print \$4}'")"
log "Arquitectura: ${ARCH}"
log "Espacio libre en /overlay: ${AVAIL_KB} KiB"
[[ "${AVAIL_KB}" =~ ^[0-9]+$ ]] || die "no se pudo leer el espacio libre"

if (( AVAIL_KB < 700 )); then
  if [[ "${FORCE}" -eq 1 ]]; then
    log "ADVERTENCIA: espacio bajo; continuando por --force"
  else
    die "espacio insuficiente (${AVAIL_KB} KiB). Ver plan (retirar paquetes o extroot USB) o usar --force"
  fi
fi

# --- 3. Paquete tor ----------------------------------------------------------
if router_ssh "opkg list-installed 2>/dev/null | grep -q '^tor '"; then
  log "Paquete tor ya instalado: $(router_ssh "opkg list-installed | awk '/^tor / {print \$3}'")"
else
  log "opkg update"
  router_ssh "opkg update" || die "opkg update fallo (revisar Internet/espacio)"
  log "Instalando tor"
  router_ssh "opkg install tor" || die "opkg install tor fallo"
  router_ssh "opkg list-installed | grep '^tor '" || die "tor no aparece instalado"
fi

# --- 4. Directorio persistente del hidden service ---------------------------
log "Preparando ${HIDDEN_SERVICE_DIR}"
router_ssh "
  set -e
  mkdir -p '${HIDDEN_SERVICE_DIR}'
  chmod 700 '${HIDDEN_SERVICE_DIR}'
  if id tor >/dev/null 2>&1; then
    chown -R tor:tor '${HIDDEN_SERVICE_DIR}'
  fi
" || die "no se pudo preparar ${HIDDEN_SERVICE_DIR}"

# --- 5. torrc ---------------------------------------------------------------
log "Escribiendo /etc/tor/torrc"
router_ssh "cat > /etc/tor/torrc" <<TORRC
# Generado por mr3420-onion-server (04_install_tor.sh)
# Hidden service v3 persistente. NO mover a /var (tmpfs).

HiddenServiceDir ${HIDDEN_SERVICE_DIR}
HiddenServiceVersion 3
HiddenServicePort ${ONION_PORT} ${LOCAL_SERVICE_IP}:${LOCAL_SERVICE_PORT}
TORRC

router_ssh "chmod 644 /etc/tor/torrc"

# --- 6. Arranque y espera de la address -------------------------------------
log "Habilitando y reiniciando Tor"
router_ssh "/etc/init.d/tor enable; /etc/init.d/tor restart" || die "no se pudo reiniciar Tor"

ONION=""
for _ in $(seq 1 40); do
  ONION="$(router_ssh "cat '${HIDDEN_SERVICE_DIR}/hostname' 2>/dev/null" || true)"
  [[ "${ONION}" == *.onion ]] && break
  sleep 3
done
[[ "${ONION}" == *.onion ]] || {
  router_ssh "logread -e tor | tail -n 40" || true
  die "Tor no genero ${HIDDEN_SERVICE_DIR}/hostname (ver log anterior)"
}
log "Direccion onion: ${ONION}"

# Guardar en config (gitignored)
if grep -q '^ONION_ADDRESS=' "${CONFIG_FILE}"; then
  sed -i "s|^ONION_ADDRESS=.*|ONION_ADDRESS=${ONION}|" "${CONFIG_FILE}"
else
  printf 'ONION_ADDRESS=%s\n' "${ONION}" >> "${CONFIG_FILE}"
fi

# --- 7. Diagnostico ----------------------------------------------------------
BOOTSTRAP="$(router_ssh "logread -e tor | grep -c 'Bootstrapped 100%' || true")"
if [[ "${BOOTSTRAP}" =~ ^[0-9]+$ ]] && (( BOOTSTRAP > 0 )); then
  log "Bootstrap: 100% confirmado en logread"
else
  log "ADVERTENCIA: aun no se observa 'Bootstrapped 100%' (puede tardar; revisar logread -e tor)"
fi

log "Proceso: $(router_ssh "pgrep -f '/usr/sbin/tor' | head -n1" || true)"
router_ssh "logread -e tor | tail -n 20" || true
log "Listo. Siguiente: ./scripts/05_deploy_uhttpd.sh"
