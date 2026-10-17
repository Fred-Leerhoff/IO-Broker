#!/bin/sh
# QNAP TS-1273AU: einmalige Einrichtung des ioBroker Pull-Deployers
set -eu

REPO_DIR="${IOBROKER_REPO_DIR:-/share/Container/IO-Broker}"
STATE_DIR="${REPO_DIR}/runtime/deploy"
BACKUP_DIR="${REPO_DIR}/runtime/backups"
DATA_DIR="/share/Container/iobroker/data"
CRON_FILE="/etc/config/crontab"
CRON_MARK="# IO-Broker GitHub pull deployer"
CRON_ENTRY="*/5 * * * * /bin/sh ${REPO_DIR}/scripts/qnap_deploy.sh >/dev/null 2>&1"

if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte als QNAP admin/root via SSH ausfuehren." >&2
  exit 1
fi
if [ ! -d "${REPO_DIR}/.git" ] || [ ! -f "${REPO_DIR}/compose.yaml" ]; then
  echo "Repository fehlt unter ${REPO_DIR}; zuerst deploy/qnap klonen." >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose V2 nicht gefunden. Container Station 3 pruefen." >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "curl fehlt auf dem QNAP (fuer den Healthcheck erforderlich)." >&2
  exit 1
fi
if [ ! -f "${CRON_FILE}" ]; then
  echo "QNAP-Crontab nicht gefunden: ${CRON_FILE}" >&2
  exit 1
fi

mkdir -p "${STATE_DIR}" "${BACKUP_DIR}" "${DATA_DIR}"
chmod 700 "${STATE_DIR}" "${BACKUP_DIR}"
tmp="${STATE_DIR}/crontab.$$"
trap 'rm -f "${tmp}"' EXIT HUP INT TERM
grep -vF "${REPO_DIR}/scripts/qnap_deploy.sh" "${CRON_FILE}" > "${tmp}" || true
{
  cat "${tmp}"
  echo "${CRON_MARK}"
  echo "${CRON_ENTRY}"
} > "${CRON_FILE}"
crontab "${CRON_FILE}"
if [ -x /etc/init.d/crond.sh ]; then
  /etc/init.d/crond.sh restart >/dev/null 2>&1 || true
fi

echo "ioBroker Pull-Deployer eingerichtet: Branch deploy/qnap, Pruefung alle 5 Minuten."
echo "Erstes Deployment wird jetzt gestartet."
/bin/sh "${REPO_DIR}/scripts/qnap_deploy.sh"
echo "Log: ${STATE_DIR}/deploy.log"
