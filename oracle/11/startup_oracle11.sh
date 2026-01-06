#!/bin/bash
set -u

# ===== CONFIG =====
ORACLE_SID="XE"
ORACLE_HOME="/u01/app/oracle/product/11.2.0/xe"
ORACLE_USER="oracle"

START_LISTENER=true
LISTENER_NAME="LISTENER"

# Log en HOME (fallback /tmp)
LOG_DIR="${HOME}/logs"
mkdir -p "${LOG_DIR}" 2>/dev/null || LOG_DIR="/tmp"
LOG_FILE="${LOG_DIR}/startup_${ORACLE_SID}_$(date +%Y%m%d_%H%M%S).log"

log() {
  local msg="[$(date)] $*"
  echo "${msg}"
  echo "${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

run_sql() {
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

log "Iniciando arranque Oracle 11g XE - SID=${ORACLE_SID}"
log "Log: ${LOG_FILE}"

# ===== PRECHECK (PMON) =====
PMON_COUNT=$(ps -ef | grep -v grep | grep -E -c "(ora|xe)_pmon_${ORACLE_SID}" || true)
if [[ "${PMON_COUNT}" -gt 0 ]]; then
  log "La instancia ya está arriba (PMON encontrado)."
else
  log "Ejecutando startup..."
  OUT_START=$(run_sql "startup;")
  RC_START=$?

  echo "${OUT_START}" >> "${LOG_FILE}" 2>/dev/null || true

  if [[ "${RC_START}" -ne 0 ]]; then
    log "ERROR: startup falló (rc=${RC_START})"
    log "Salida sqlplus (startup):"
    echo "${OUT_START}"
    exit 2
  fi

  log "startup exitoso"
fi

# ===== LISTENER (OPCIONAL) =====
if [[ "${START_LISTENER}" == "true" ]]; then
  log "Levantando listener ${LISTENER_NAME}..."
  if ! lsnrctl start "${LISTENER_NAME}" >> "${LOG_FILE}" 2>&1; then
    log "WARNING: no pude levantar listener (revisa nombre o estado)"
  else
    log "Listener levantado"
  fi
fi

# ===== POSTCHECK =====
PMON_AFTER=$(ps -ef | grep -v grep | grep -E -c "(ora|xe)_pmon_${ORACLE_SID}" || true)
if [[ "${PMON_AFTER}" -eq 0 ]]; then
  log "ERROR: No se detecta PMON después del startup."
  exit 3
fi

log "Arranque completado"
exit 0
