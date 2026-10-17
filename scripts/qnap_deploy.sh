#!/bin/sh
# QNAP: nur freigegebene GitHub-Versionen aus deploy/qnap ausrollen
set -eu

PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH
REPO_DIR="${IOBROKER_REPO_DIR:-/share/Container/IO-Broker}"
DEPLOY_BRANCH="deploy/qnap"
STATE_DIR="${REPO_DIR}/runtime/deploy"
BACKUP_DIR="${REPO_DIR}/runtime/backups"
DATA_DIR="/share/Container/iobroker/data"
LOG_FILE="${STATE_DIR}/deploy.log"
LAST_ATTEMPTED="${STATE_DIR}/last_attempted_sha"
LAST_GOOD="${STATE_DIR}/last_good_sha"
LAST_FAILED="${STATE_DIR}/last_failed_sha"
LOCK_DIR="${STATE_DIR}/deploy.lock"

mkdir -p "${STATE_DIR}" "${BACKUP_DIR}"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "${LOG_FILE}"; }

# Ein zweiter Cron-Lauf darf den laufenden Rollout nicht unterbrechen.
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then exit 0; fi
cleanup() { rmdir "${LOCK_DIR}" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM

if [ ! -d "${REPO_DIR}/.git" ] || ! command -v docker >/dev/null 2>&1; then
  log "ERROR Repository oder Docker nicht vorhanden."
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  log "ERROR Docker Compose V2 nicht verfuegbar."
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  log "ERROR curl nicht verfuegbar."
  exit 1
fi

# Public-Repo: read-only GitHub-Zugriff via HTTPS, kein privater Deploy-Key noetig.
git_cmd() {
  docker run --rm -v "${REPO_DIR}:/repo" alpine/git \
    -c safe.directory=/repo -C /repo "$@"
}
remote_line="$(git_cmd ls-remote origin "refs/heads/${DEPLOY_BRANCH}" 2>/dev/null || true)"
remote_sha="$(printf '%s\n' "${remote_line}" | awk 'NR==1 {print $1}')"
if [ -z "${remote_sha}" ]; then
  log "INFO Branch ${DEPLOY_BRANCH} nicht erreichbar."
  exit 0
fi
if [ -f "${LAST_ATTEMPTED}" ] && [ "$(cat "${LAST_ATTEMPTED}")" = "${remote_sha}" ]; then
  exit 0
fi

log "START candidate ${remote_sha}"
if ! git_cmd fetch --no-tags origin "${DEPLOY_BRANCH}" >> "${LOG_FILE}" 2>&1; then
  log "ERROR Git fetch fehlgeschlagen."
  exit 1
fi
fetched_sha="$(git_cmd rev-parse FETCH_HEAD 2>/dev/null || true)"
if [ "${fetched_sha}" != "${remote_sha}" ]; then
  log "ERROR Commit geaendert waehrend Git-Fetch; neuer Versuch spaeter."
  exit 1
fi
# Ab hier nicht alle 5 Minuten erneut dieselbe fehlgeschlagene Version versuchen.
printf '%s\n' "${remote_sha}" > "${LAST_ATTEMPTED}"
previous_good=""
if [ -f "${LAST_GOOD}" ]; then previous_good="$(cat "${LAST_GOOD}")"; fi

# Bereits existierende, aber fremd verwaltete Container nie ersetzen.
existing=0
if docker inspect iobroker >/dev/null 2>&1; then
  existing=1
  project="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' iobroker 2>/dev/null || true)"
  if [ "${project}" != "iobroker" ] || [ -z "${previous_good}" ]; then
    log "ERROR Bereits vorhandener iobroker-Container ohne bekanntes Deployment. Abbruch."
    printf '%s\n' "${remote_sha}" > "${LAST_FAILED}"
    exit 1
  fi
fi

if ! git_cmd checkout -f -B "${DEPLOY_BRANCH}" "${remote_sha}" >> "${LOG_FILE}" 2>&1; then
  log "ERROR Git checkout fehlgeschlagen."
  printf '%s\n' "${remote_sha}" > "${LAST_FAILED}"
  exit 1
fi
if ! docker compose -p iobroker -f "${REPO_DIR}/compose.yaml" config -q >> "${LOG_FILE}" 2>&1; then
  log "ERROR Docker Compose Konfiguration ungueltig."
  printf '%s\n' "${remote_sha}" > "${LAST_FAILED}"
  exit 1
fi
if ! docker compose -p iobroker -f "${REPO_DIR}/compose.yaml" pull iobroker >> "${LOG_FILE}" 2>&1; then
  log "ERROR Image konnte nicht heruntergeladen werden. Laufende Version bleibt."
  printf '%s\n' "${remote_sha}" > "${LAST_FAILED}"
  exit 1
fi

mkdir -p "${DATA_DIR}"
if [ "${existing}" -eq 1 ]; then
  # Konsistente Sicherung: vor der Archivierung den ioBroker anhalten.
  if ! docker stop iobroker >> "${LOG_FILE}" 2>&1; then
    log "ERROR Container konnte nicht angehalten werden."
    printf '%s\n' "${remote_sha}" > "${LAST_FAILED}"
    exit 1
  fi
  short_sha="$(printf '%s' "${remote_sha}" | cut -c1-12)"
  backup="${BACKUP_DIR}/iobroker_pre_deploy_$(date +%Y%m%d_%H%M%S)_${short_sha}.tar.gz"
  if ! tar -czf "${backup}.tmp" -C "${DATA_DIR}" . >> "${LOG_FILE}" 2>&1; then
    rm -f "${backup}.tmp"
    docker start iobroker >> "${LOG_FILE}" 2>&1 || true
    log "ERROR Sicherung fehlgeschlagen; alten Container wieder gestartet."
    printf '%s\n' "${remote_sha}" > "${LAST_FAILED}"
    exit 1
  fi
  mv "${backup}.tmp" "${backup}"
  log "BACKUP ${backup}"
fi

if ! docker compose -p iobroker -f "${REPO_DIR}/compose.yaml" up -d --no-deps --force-recreate iobroker >> "${LOG_FILE}" 2>&1; then
  log "ERROR Container konnte nicht gestartet werden."
  deployment_ok=0
else
  deployment_ok=0
  n=0
  while [ "${n}" -lt 30 ]; do
    running="$(docker inspect -f '{{.State.Running}}' iobroker 2>/dev/null || true)"
    status="$(curl -s -o /dev/null --connect-timeout 2 --max-time 4 -w '%{http_code}' http://127.0.0.1:18081/ 2>/dev/null || true)"
    case "${status}" in
      2*|3*|401|403)
        if [ "${running}" = "true" ]; then deployment_ok=1; break; fi
        ;;
    esac
    sleep 10
    n=$((n + 1))
  done
fi

if [ "${deployment_ok}" -ne 1 ]; then
  log "ERROR Healthcheck fehlgeschlagen; Rollback wird versucht."
  printf '%s\n' "${remote_sha}" > "${LAST_FAILED}"
  if [ -n "${previous_good}" ]; then
    if git_cmd checkout -f -B "${DEPLOY_BRANCH}" "${previous_good}" >> "${LOG_FILE}" 2>&1; then
      docker compose -p iobroker -f "${REPO_DIR}/compose.yaml" up -d --no-deps --force-recreate iobroker >> "${LOG_FILE}" 2>&1 || true
      log "ROLLBACK Image/Konfiguration auf ${previous_good} versucht (Daten nicht automatisch wiederhergestellt)."
    fi
  fi
  exit 1
fi

printf '%s\n' "${remote_sha}" > "${LAST_GOOD}"
rm -f "${LAST_FAILED}"
log "SUCCESS ${remote_sha}, HTTP ${status}"
