#!/usr/bin/env bash
# =============================================================================
# 05_deploy_uhttpd.sh — Pagina estatica en 127.0.0.1:8080
# =============================================================================
# Publica www/index.html mediante una instancia dedicada de uhttpd que
# escucha SOLO en loopback. Tor la expone como onion:80.
#
# Que hace:
#   1. Copia www/index.html a /www/onion/index.html en el router.
#   2. Crea/actualiza la seccion UCI uhttpd.onion:
#        listen_http=127.0.0.1:8080, home=/www/onion,
#        sin CGI/Lua/ubus, sin listados de directorio.
#   3. Reinicia uhttpd y verifica que responde en loopback.
#   4. Comprueba que el puerto 8080 NO escucha en la LAN.
#
# Uso:
#   ./scripts/05_deploy_uhttpd.sh
#
# LuCI y la instancia uhttpd por defecto NO se tocan ni se exponen por onion.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROYECTO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROYECTO_DIR}/config"
KNOWN_HOSTS="${PROYECTO_DIR}/.ssh_known_hosts"
INDEX_FILE="${PROYECTO_DIR}/www/index.html"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: no existe ${CONFIG_FILE}." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

[[ -f "${INDEX_FILE}" ]] || { echo "ERROR: falta ${INDEX_FILE}" >&2; exit 1; }

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

command -v ssh >/dev/null 2>&1 || die "falta ssh"
command -v sshpass >/dev/null 2>&1 || die "falta sshpass"
command -v scp >/dev/null 2>&1 || die "falta scp"
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
router_scp() {
  sshpass -p "${ROOT_PASSWORD}" scp "${SSH_OPTS[@]}" "$@"
}

router_ssh "true" >/dev/null 2>&1 || die "sin SSH en ${ROUTER_IP}; ejecutar 03_ssh_setup.sh"
log "SSH OK en ${ROUTER_IP}"

# --- 1. Copiar contenido -----------------------------------------------------
log "Copiando index.html a /www/onion/"
router_ssh "mkdir -p /www/onion && chmod 755 /www/onion"
router_scp "${INDEX_FILE}" "${ROUTER_USER}@${ROUTER_IP}:/www/onion/index.html" \
  || die "fallo scp de index.html"
router_ssh "chmod 644 /www/onion/index.html"

# --- 2. Instancia uhttpd dedicada -------------------------------------------
log "Configurando instancia uhttpd 'onion' en ${LOCAL_SERVICE_IP}:${LOCAL_SERVICE_PORT}"
router_ssh "
  set -e
  if ! uci -q get uhttpd.onion >/dev/null 2>&1; then
    uci set uhttpd.onion=uhttpd
  fi
  uci set uhttpd.onion.listen_http='${LOCAL_SERVICE_IP}:${LOCAL_SERVICE_PORT}'
  uci set uhttpd.onion.home='/www/onion'
  uci set uhttpd.onion.cgi_prefix=''
  uci set uhttpd.onion.lua_prefix=''
  uci set uhttpd.onion.ubus_prefix=''
  uci set uhttpd.onion.no_dirlists='1'
  uci set uhttpd.onion.rfc1918_filter='1'
  uci set uhttpd.onion.max_requests='3'
  uci commit uhttpd
" || die "fallo la configuracion UCI de uhttpd"

log "Reiniciando uhttpd"
router_ssh "/etc/init.d/uhttpd enable; /etc/init.d/uhttpd restart" \
  || die "no se pudo reiniciar uhttpd"

# --- 3. Verificacion local ---------------------------------------------------
BODY=""
for _ in $(seq 1 15); do
  BODY="$(router_ssh "wget -qO- http://${LOCAL_SERVICE_IP}:${LOCAL_SERVICE_PORT}/ 2>/dev/null" || true)"
  [[ -n "${BODY}" ]] && break
  sleep 1
done
[[ -n "${BODY}" ]] || die "uhttpd no responde en ${LOCAL_SERVICE_IP}:${LOCAL_SERVICE_PORT}"
printf '%s' "${BODY}" | grep -q 'Nodo Onion' \
  || die "la respuesta HTTP no contiene el contenido esperado"
log "HTTP local OK ($(printf '%s' "${BODY}" | wc -c) bytes)"

# --- 4. Confirmar escucha solo en loopback ----------------------------------
LISTEN="$(router_ssh "netstat -lntp 2>/dev/null | grep ':${LOCAL_SERVICE_PORT} ' || true")"
[[ -n "${LISTEN}" ]] || die "no se observa ${LOCAL_SERVICE_PORT} en netstat"
if printf '%s\n' "${LISTEN}" | grep -vq '127\.0\.0\.1'; then
  printf '%s\n' "${LISTEN}" >&2
  die "el puerto ${LOCAL_SERVICE_PORT} esta expuesto fuera de loopback"
fi
log "Escucha confirmada: $(printf '%s' "${LISTEN}" | tr -s ' ')"

# --- 5. Confirmar mapeo Tor --------------------------------------------------
TORRC="$(router_ssh "grep -E '^HiddenServicePort' /etc/tor/torrc || true")"
log "Mapeo Tor: ${TORRC:-NO DEFINIDO}"
printf '%s' "${TORRC}" | grep -q "${ONION_PORT} ${LOCAL_SERVICE_IP}:${LOCAL_SERVICE_PORT}" \
  || die "torrc no mapea onion:${ONION_PORT} a ${LOCAL_SERVICE_IP}:${LOCAL_SERVICE_PORT}"

log "Listo. Siguiente: ./scripts/06_wifi_ap.sh"
