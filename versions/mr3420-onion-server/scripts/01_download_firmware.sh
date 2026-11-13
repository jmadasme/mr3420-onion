#!/usr/bin/env bash
# =============================================================================
# 01_download_firmware.sh — Descarga y verificacion de la imagen OpenWrt
# =============================================================================
# Descarga la imagen oficial de OpenWrt 24.10.8 para el TL-MR3420 v5,
# verifica SHA256 y tamano, y crea la copia firmware/tp_recovery.bin que
# espera el bootloader U-Boot por TFTP.
#
# Uso:
#   ./scripts/01_download_firmware.sh
#
# Requiere: wget, sha256sum, awk, stat. No instala nada.
# Idempotente: si la imagen ya existe y su SHA256 coincide, no descarga.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROYECTO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROYECTO_DIR}/config"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: no existe ${CONFIG_FILE}. Copiar config.example a config." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

FIRMWARE_DIR="${PROYECTO_DIR}/firmware"
FIRMWARE_FILE="${FIRMWARE_DIR}/$(basename "${FIRMWARE_URL}")"
RECOVERY_FILE="${FIRMWARE_DIR}/${TFTP_FILENAME}"
MIN_SIZE_BYTES=1000000

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

verify_sha256() {
  local file="$1" sum
  [[ -f "${file}" ]] || return 1
  sum="$(sha256sum "${file}" | awk '{print $1}')"
  [[ "${sum}" == "${FIRMWARE_SHA256}" ]]
}

command -v wget     >/dev/null 2>&1 || die "wget no esta disponible"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum no esta disponible"

mkdir -p "${FIRMWARE_DIR}"

# --- 1. Imagen original -------------------------------------------------------
if verify_sha256 "${FIRMWARE_FILE}"; then
  log "Imagen ya presente y verificada: ${FIRMWARE_FILE}"
else
  if [[ -f "${FIRMWARE_FILE}" ]]; then
    log "SHA256 invalido en la imagen existente; se elimina y re-descarga"
    rm -f "${FIRMWARE_FILE}"
  fi

  log "Descargando imagen oficial OpenWrt 24.10.8..."
  log "URL: ${FIRMWARE_URL}"
  if ! wget --https-only --timeout=30 --tries=3 \
            --output-document="${FIRMWARE_FILE}.part" "${FIRMWARE_URL}"; then
    rm -f "${FIRMWARE_FILE}.part"
    die "fallo la descarga de la imagen"
  fi
  mv -f "${FIRMWARE_FILE}.part" "${FIRMWARE_FILE}"

  if ! verify_sha256 "${FIRMWARE_FILE}"; then
    local_sum="$(sha256sum "${FIRMWARE_FILE}" | awk '{print $1}')"
    rm -f "${FIRMWARE_FILE}"
    die "SHA256 no coincide. Esperado=${FIRMWARE_SHA256} obtenido=${local_sum}"
  fi
fi

# --- 2. Copia con el nombre que pide U-Boot ----------------------------------
if ! cmp -s "${FIRMWARE_FILE}" "${RECOVERY_FILE}"; then
  log "Copiando a ${RECOVERY_FILE}"
  cp -f "${FIRMWARE_FILE}" "${RECOVERY_FILE}"
fi
verify_sha256 "${RECOVERY_FILE}" || die "la copia ${TFTP_FILENAME} no pasa SHA256"

SIZE_BYTES="$(stat -c %s "${RECOVERY_FILE}")"
[[ "${SIZE_BYTES}" -ge "${MIN_SIZE_BYTES}" ]] || die "tamano sospechoso: ${SIZE_BYTES} bytes"

# --- 3. Resumen --------------------------------------------------------------
log "OK: SHA256 verificado"
log "OK: tamano ${SIZE_BYTES} bytes ($(( SIZE_BYTES / 1024 )) KiB)"
log "Imagen TFTP lista: ${RECOVERY_FILE}"
sha256sum "${FIRMWARE_FILE}" "${RECOVERY_FILE}"
