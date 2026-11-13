#!/usr/bin/env bash
# =============================================================================
# 07_verify.sh — Verificacion final y persistencia del servicio onion
# =============================================================================
# Comprueba, desde la notebook:
#   - Proceso Tor y bootstrap 100%.
#   - Hidden service: hostname + private_key persistentes.
#   - uhttpd escuchando SOLO en 127.0.0.1:8080 y respondiendo el HTML.
#   - Servicios habilitados en el arranque (tor, uhttpd, firewall).
#   - Wi-Fi AP y firewall (WAN cerrada).
#   - Acceso .onion desde un cliente Tor local, si ya existe (no instala nada).
#   - Persistencia de la direccion .onion tras reboot (con --reboot).
#
# Uso:
#   ./scripts/07_verify.sh [--reboot]
#
# Con --reboot el script reinicia el router y espera a que vuelva. La sesion
# SSH se corta (es esperado). No instala herramientas en la notebook.
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

DO_REBOOT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reboot) DO_REBOOT=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "ERROR: opcion desconocida: $1" >&2; exit 1 ;;
  esac
done

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '[%s] OK   %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { printf '[%s] FAIL %s\n' "$(date +%H:%M:%S)" "$*"; CRITICAL_FAIL=1; }
die()  { echo "ERROR: $*" >&2; exit 1; }

CRITICAL_FAIL=0
command -v ssh >/dev/null 2>&1 || die "falta ssh"
command -v sshpass >/dev/null 2>&1 || die "falta sshpass"
command -v nc >/dev/null 2>&1 || die "falta nc"
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
wait_for_tcp() {
  local host="$1" port="$2" seconds="$3" i
  for ((i = 0; i < seconds; i++)); do
    nc -z -w 2 "${host}" "${port}" 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

router_ssh "true" >/dev/null 2>&1 || die "sin SSH en ${ROUTER_IP}; ejecutar 03_ssh_setup.sh"
log "Verificando ${ROUTER_IP}"

# --- 1. Tor ------------------------------------------------------------------
if router_ssh "pgrep -f '/usr/sbin/tor' >/dev/null 2>&1"; then
  ok "proceso tor activo (PID $(router_ssh "pgrep -f '/usr/sbin/tor' | head -n1"))"
else
  fail "proceso tor NO activo"
fi

ONION="$(router_ssh "cat '${HIDDEN_SERVICE_DIR}/hostname' 2>/dev/null" || true)"
if [[ "${ONION}" =~ ^[a-z2-7]{56}\.onion$ ]]; then
  ok "hidden service hostname: ${ONION}"
else
  fail "hostname .onion invalido o ausente: '${ONION}'"
fi

if router_ssh "test -s '${HIDDEN_SERVICE_DIR}/private_key'"; then
  ok "private_key presente (persistente en ${HIDDEN_SERVICE_DIR})"
else
  fail "private_key ausente: la address no seria estable"
fi

if router_ssh "logread -e tor 2>/dev/null | grep -q 'Bootstrapped 100%'"; then
  ok "Tor bootstrap 100%"
else
  warn "no se observa 'Bootstrapped 100%' en logread (puede estar arrancando)"
fi

if router_ssh "/etc/init.d/tor enabled >/dev/null 2>&1"; then
  ok "tor habilitado en el arranque"
else
  fail "tor NO esta habilitado en el arranque"
fi

# --- 2. uhttpd local ---------------------------------------------------------
if router_ssh "netstat -lntp 2>/dev/null | grep -q '127.0.0.1:${LOCAL_SERVICE_PORT}'"; then
  ok "uhttpd escucha en 127.0.0.1:${LOCAL_SERVICE_PORT}"
else
  fail "uhttpd NO escucha en 127.0.0.1:${LOCAL_SERVICE_PORT}"
fi

if router_ssh "netstat -lntp 2>/dev/null | grep ':${LOCAL_SERVICE_PORT} ' | grep -vq '127.0.0.1'"; then
  fail "el puerto ${LOCAL_SERVICE_PORT} esta expuesto fuera de loopback"
else
  ok "puerto ${LOCAL_SERVICE_PORT} solo en loopback"
fi

if router_ssh "wget -qO- http://${LOCAL_SERVICE_IP}:${LOCAL_SERVICE_PORT}/ 2>/dev/null | grep -q 'Nodo Onion'"; then
  ok "HTTP local devuelve el HTML esperado"
else
  fail "HTTP local no devuelve el HTML esperado"
fi

if router_ssh "/etc/init.d/uhttpd enabled >/dev/null 2>&1"; then
  ok "uhttpd habilitado en el arranque"
else
  fail "uhttpd NO esta habilitado en el arranque"
fi

TORRC_MAP="$(router_ssh "grep -E '^HiddenServicePort' /etc/tor/torrc 2>/dev/null" || true)"
if printf '%s' "${TORRC_MAP}" | grep -q "${ONION_PORT} ${LOCAL_SERVICE_IP}:${LOCAL_SERVICE_PORT}"; then
  ok "mapeo torrc: ${TORRC_MAP}"
else
  fail "mapeo torrc incorrecto: '${TORRC_MAP}'"
fi

# --- 3. Wi-Fi y firewall -----------------------------------------------------
SSID="$(router_ssh "uci -q get wireless.default_radio0.ssid 2>/dev/null || true")"
if [[ "${SSID}" == "${WIFI_SSID}" ]]; then
  ok "Wi-Fi AP configurado: ${SSID}"
else
  warn "SSID esperado '${WIFI_SSID}', obtenido '${SSID}'"
fi

WAN_INPUT="$(router_ssh "uci -q get firewall.@zone[1].input 2>/dev/null || true")"
if [[ "${WAN_INPUT}" == "REJECT" ]]; then
  ok "firewall WAN input=REJECT"
else
  fail "firewall WAN input='${WAN_INPUT}' (se esperaba REJECT)"
fi

# --- 4. Acceso onion desde la notebook (sin instalar nada) -------------------
onion_http_test() {
  local proxy_cmd="$1"
  # shellcheck disable=SC2086
  ${proxy_cmd} "http://${ONION}/" 2>/dev/null | grep -q 'Nodo Onion'
}
if [[ -n "${ONION}" ]]; then
  if command -v torsocks >/dev/null 2>&1 && \
     ss -lnt 2>/dev/null | grep -q ':9050 '; then
    if onion_http_test "torsocks curl -fsS --max-time 60"; then
      ok "acceso .onion verificado via torsocks"
    else
      warn "torsocks no pudo acceder al .onion (revisar cliente Tor)"
    fi
  elif command -v curl >/dev/null 2>&1 && \
       ss -lnt 2>/dev/null | grep -q ':9050 '; then
    if onion_http_test "curl -fsS --max-time 60 --socks5-hostname 127.0.0.1:9050"; then
      ok "acceso .onion verificado via curl + SOCKS 9050"
    else
      warn "curl no pudo acceder al .onion (revisar cliente Tor)"
    fi
  else
    warn "sin cliente Tor local (torsocks o SOCKS 9050); acceso .onion queda pendiente"
    warn "no se instala nada: verificar desde un navegador Tor externo con ${ONION}"
  fi
fi

# --- 5. Persistencia tras reboot --------------------------------------------
if [[ "${DO_REBOOT}" -eq 1 ]]; then
  BEFORE="${ONION}"
  log "Reiniciando el router para probar persistencia"
  router_ssh "sync; reboot" >/dev/null 2>&1 || true

  log "Esperando a que el router se apague..."
  for _ in $(seq 1 60); do
    ping -c 1 -W 1 "${ROUTER_IP}" >/dev/null 2>&1 || break
    sleep 1
  done

  log "Esperando a que SSH vuelva (max 300s)..."
  if ! wait_for_tcp "${ROUTER_IP}" 22 300; then
    fail "el router no volvio tras el reboot"
  else
    sleep 10
    AFTER="$(router_ssh "cat '${HIDDEN_SERVICE_DIR}/hostname' 2>/dev/null" || true)"
    if [[ "${BEFORE}" == "${AFTER}" && -n "${AFTER}" ]]; then
      ok "persistencia confirmada: ${AFTER}"
    else
      fail "la address cambio tras reboot: antes='${BEFORE}' despues='${AFTER}'"
    fi
    if router_ssh "wget -qO- http://${LOCAL_SERVICE_IP}:${LOCAL_SERVICE_PORT}/ 2>/dev/null | grep -q 'Nodo Onion'"; then
      ok "servicio local sigue respondiendo tras reboot"
    else
      fail "servicio local no responde tras reboot"
    fi
  fi
else
  log "Persistencia no probada en esta corrida. Ejecutar: ./scripts/07_verify.sh --reboot"
fi

# --- 6. Resumen --------------------------------------------------------------
log "Direccion onion: ${ONION:-NO DISPONIBLE}"
if [[ "${CRITICAL_FAIL}" -eq 0 ]]; then
  ok "verificacion completada sin fallos criticos"
  exit 0
else
  fail "verificacion completada con fallos criticos"
  exit 1
fi
