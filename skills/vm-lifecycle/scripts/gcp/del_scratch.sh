#!/usr/bin/env bash
# Delete the scratch disk. ALL DATA ON IT IS LOST (it is never snapshotted).
# A running VM: unmount over ssh and detach while it keeps running; if the mount is
# busy, the VM is stopped first (and stays stopped). A stopped VM: just detach.
# usage: del_scratch.sh NAME [--yes]     (without --yes: prints the plan only)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; shift || true
YES=0
while [[ $# -gt 0 ]]; do case "$1" in --yes) YES=1; shift ;;
  *) die "usage: del_scratch.sh NAME [--yes]" ;; esac; done
DISK="${NAME}-scratch"
STATUS="$(vm_status)"
[[ -n "${STATUS}" ]] || die "instance ${NAME} not found"
SIZE="$(gcloud compute disks describe "${DISK}" "${GC[@]}" --format='value(sizeGb)' 2>/dev/null || true)"
if [[ -z "${SIZE}" ]]; then log "${NAME} has no scratch disk (${DISK})."; exit 0; fi
case "${STATUS}" in
  RUNNING)    HOW="unmount it live (stopping ${NAME} first if it is busy), then " ;;
  TERMINATED) HOW="" ;;
  *)          HOW="stop ${NAME} (${STATUS}), then " ;;
esac
log "Will: ${HOW}detach and DELETE ${DISK} (${SIZE} GB). All data on it is lost; there is no snapshot."
((YES)) || { log "Not doing it: re-run with --yes."; exit 0; }

if [[ "${STATUS}" == RUNNING ]]; then
  ssh -o BatchMode=yes "${NAME}" 'sudo umount /mnt/scratch 2>/dev/null || ! mountpoint -q /mnt/scratch' \
    || { log "could not unmount /mnt/scratch (busy?); stopping ${NAME} instead"; stop_vm; }
elif [[ "${STATUS}" != TERMINATED ]]; then
  stop_vm
fi
if [[ -n "$(attached_disk scratch)" ]]; then
  log "Detaching ${DISK}..."
  gcloud compute instances detach-disk "${NAME}" "${GC[@]}" --disk="${DISK}" \
    || log "detach reported an error; checking whether it went through..."
  poll 36 scratch_none || die "${DISK} is still attached"
fi
log "Deleting ${DISK}..."
gcloud compute disks delete "${DISK}" "${GC[@]}" --quiet || log "delete reported an error; checking whether it went through..."
poll 36 gone disks "${DISK}" || die "${DISK} still exists"
log "Scratch disk deleted."
