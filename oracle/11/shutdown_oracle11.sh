#!/bin/bash
set -u

# ===== CONFIG =====
ORACLE_SID="XE"
ORACLE_HOME="/u01/app/oracle/product/11.2.0/xe"
ORACLE_USER="oracle"

STOP_LISTENER=true
LISTENER_NAME="LISTENER"

# Log en HOME (fallback /tmp)
LOG_DIR="${HOME}/logs"
mkdir -p "${LOG_DIR}" 2>/dev/null || LOG_DIR="/tmp"
LOG_FILE="${LOG_DIR}/shutdown_${ORACLE_SID}_$(date +%Y%m%d_%H%M%S).log"

log() {
  local msg="[$(date)] $*"
  echo "${msg}"
  echo "${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

run_sql() {
  # corre sqlplus y guarda salida en variable
  local sql="$1"
  local out
  out=$(sqlplus -s / as sysdba <<SQL
whenever sqlerror exit 1;
${sql}
exit;
SQL
)
  local rc=$?
  echo "${out}"
  return $rc
}

# ===== VALIDACIONES =====
if [[ "$(whoami)" != "${ORACLE_USER}" ]]; then
  echo "ERROR: Ejecuta como usuario ${ORACLE_USER}"
  exit 1
fi

export ORACLE_SID ORACLE_HOME
export PATH="$ORACLE_HOME/bin:$PATH"

log "Iniciando apagado Oracle 11g XE - SID=${ORACLE_SID}"
log "Log: ${LOG_FILE}"

# ===== PRECHECK (PMON) =====
PMON_COUNT=$(ps -ef | grep -v grep | grep -E -c "(ora|xe)_pmon_${ORACLE_SID}" || true)
if [[ "${PMON_COUNT}" -eq 0 ]]; then
  log "La instancia ya está abajo (PMON no encontrado)"
  exit 0
fi

# ===== SHUTDOWN IMMEDIATE =====
log "Ejecutando shutdown immediate..."
OUT_IMM=$(run_sql "shutdown immediate;")
RC_IMM=$?

echo "${OUT_IMM}" >> "${LOG_FILE}" 2>/dev/null || true

if [[ "${RC_IMM}" -ne 0 ]]; then
  log "shutdown immediate falló (rc=${RC_IMM})"
  log "Salida sqlplus (immediate):"
  echo "${OUT_IMM}"

  log "Ejecutando shutdown abort..."
  OUT_ABT=$(run_sql "shutdown abort;")
  RC_ABT=$?

  echo "${OUT_ABT}" >> "${LOG_FILE}" 2>/dev/null || true

  if [[ "${RC_ABT}" -ne 0 ]]; then
    log "ERROR: shutdown abort también falló (rc=${RC_ABT})"
    log "Salida sqlplus (abort):"
    echo "${OUT_ABT}"
    exit 2
  fi
else
  log "shutdown immediate exitoso"
fi

# ===== LISTENER (OPCIONAL) =====
if [[ "${STOP_LISTENER}" == "true" ]]; then
  log "Deteniendo listener ${LISTENER_NAME}..."
  if ! lsnrctl stop "${LISTENER_NAME}" >> "${LOG_FILE}" 2>&1; then
    log "WARNING: no pude detener listener (quizá ya estaba abajo o no existe en XE)"
  else
    log "Listener detenido"
  fi
fi

log "Apagado completado"
exit 0
