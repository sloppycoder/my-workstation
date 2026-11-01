#!/usr/bin/env bash
# Make (first time) or replace the VM's seed snapshot from its current boot disk.
# The VM is stopped for a consistent snapshot and left stopped — or, with --delete,
# deleted together with all its disks (an attached scratch disk is NOT snapshotted
# and is lost). The old seed is removed only after the new one is READY, and the VM
# is deleted only after that too. It never starts the VM.
# usage: shelve_vm.sh NAME [--delete] [--yes]     (without --yes: prints the plan only)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; shift || true
DELETE=0 YES=0
while [[ $# -gt 0 ]]; do case "$1" in --delete) DELETE=1; shift ;; --yes) YES=1; shift ;;
  *) die "usage: shelve_vm.sh NAME [--delete] [--yes]" ;; esac; done
STATUS="$(vm_status)"
[[ -n "${STATUS}" ]] || die "instance ${NAME} not found"
BOOT="$(attached_disk boot)"; SCRATCH="$(attached_disk scratch)"
SNAP="${SEED_PREFIX:-${NAME}}-seed-$(date -u +%Y%m%d-%H%M%S)"
OLD="$(seeds)"

log "Will: stop ${NAME} (${STATUS}); snapshot ${BOOT} -> ${SNAP};${OLD:+ delete old seed(s) $(echo ${OLD});}"
if ((DELETE)); then log "     then DELETE ${NAME} and its disks${SCRATCH:+ (including scratch ${SCRATCH}, data lost)}."
else log "     then leave ${NAME} stopped (scratch disk, if any, stays attached and is not snapshotted)."; fi
((YES)) || { log "Not doing it: re-run with --yes."; exit 0; }

[[ "${STATUS}" == TERMINATED ]] || stop_vm
log "Snapshotting ${BOOT} -> ${SNAP}..."
gcloud compute disks snapshot "${BOOT}" "${GC[@]}" --snapshot-names="${SNAP}" \
  --labels="station-vm-seed=${NAME}" ${SNAPSHOT_LOCATION:+--storage-location="${SNAPSHOT_LOCATION}"} \
  || log "snapshot reported an error; checking whether it went through..."
poll 120 snapshot_ready "${SNAP}" || die "snapshot ${SNAP} is not READY; old seed kept and ${NAME} untouched"
for s in ${OLD}; do
  log "Deleting old seed ${s}"; gcloud compute snapshots delete "${s}" --project="${PROJECT}" --quiet || log "could not delete ${s}"
done
if ((DELETE)); then
  log "${SNAP} is READY. Deleting ${NAME} and its disks..."
  gcloud compute instances delete "${NAME}" "${GC[@]}" --delete-disks=all --quiet \
    || log "delete reported an error; checking whether it went through..."
  poll 36 gone instances "${NAME}" || die "${NAME} still exists"
  log "Shelved. Bring it back with: create_vm.sh ${NAME}"
else
  log "Seed updated: ${SNAP}. ${NAME} is stopped."
fi
