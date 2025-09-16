#!/usr/bin/env bash
set -euo pipefail

# Load config (so AUTORIP_DEVICE/AUTORIP_FORMAT are available)
set -a
. /opt/streamingserver/config/autorip.env
set +a

DEV="${1:-${AUTORIP_DEVICE:-/dev/sr0}}"
FMT="${AUTORIP_FORMAT:-flac}"
CONF="/opt/streamingserver/autorip/abcde.${FMT}.conf"
LOCK=/var/lock/cd-autorip.lock

log(){ logger -t cd-autorip "$*"; echo "[cd-autorip] $*"; }

( flock -n 9 || { log "busy, skipping"; exit 0; }
  log "rip start on ${DEV}"
  if ! udevadm info --query=property --name "${DEV}" | grep -q '^ID_CDROM_MEDIA_AUDIO=1'; then
    log "no audio disc detected on ${DEV}"; exit 0
  fi
  abcde -d "${DEV}" -c "${CONF}" -N || { log "abcde failed"; exit 1; }
  log "rip done; tagging + moving with beets"
  beet -c /opt/streamingserver/autorip/beets.config.yaml import -q /srv/rips/staging || log "beets import nonfatal"
  rm -rf /srv/rips/staging/* /srv/rips/tmp/* || true
  find /srv/streamingserver/music/library -type d -maxdepth 1 -print -quit | xargs -r touch
  eject "${DEV}" || true
  log "finished; disc ejected"
) 9>"$LOCK"
