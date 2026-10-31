#!/usr/bin/env bash
# Remove EVERYTHING for this VM: the instance, its boot and scratch disks, every
# seed snapshot, and the local config. Irreversible.
# usage: destroy_vm.sh NAME [--yes]     (without --yes: lists what would be deleted)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; shift || true
[[ "${1:-}" == "--yes" ]] && YES=1 || YES=0
STATUS="$(vm_status)"
DISKS=""
for d in "${NAME}" "${NAME}-scratch"; do [[ -z "$(status_of disks "${d}")" ]] || DISKS+="${d} "; done
SEEDS="$(seeds 2>/dev/null)"
log "Will DELETE: instance ${NAME} (${STATUS:-absent}); disks: ${DISKS:-none}; seed snapshots: ${SEEDS:-none}; ${CONFIG_DIR}/${NAME}.env"
log "This cannot be undone."
((YES)) || { log "Not doing it: re-run with --yes."; exit 0; }
if [[ -n "${STATUS}" ]]; then
  gcloud compute instances delete "${NAME}" "${GC[@]}" --delete-disks=all --quiet || log "delete reported an error; checking whether it went through..."
  poll 60 gone instances "${NAME}" || die "${NAME} still exists"
fi
for d in ${DISKS}; do
  [[ -n "$(status_of disks "${d}")" ]] || continue   # already gone with the instance
  gcloud compute disks delete "${d}" "${GC[@]}" --quiet || log "could not delete disk ${d}"
done
for s in ${SEEDS}; do gcloud compute snapshots delete "${s}" --project="${PROJECT}" --quiet || log "could not delete ${s}"; done
rm -f "${CONFIG_DIR}/${NAME}.env"
log "Destroyed ${NAME}. (A Host ${NAME} block may remain in ~/.ssh/config.)"
