#!/usr/bin/env bash
# Delete the scratch volume. ALL DATA ON IT IS LOST (never imaged).
# A running VM: unmount over ssh and detach while it keeps running; if the mount is
# busy, the VM is stopped first (and stays stopped). A stopped VM: just detach.
# usage: del_scratch.sh NAME [--yes]     (without --yes: prints the plan only)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; shift || true
YES=0
while [[ $# -gt 0 ]]; do case "$1" in --yes) YES=1; shift ;;
  *) die "usage: del_scratch.sh NAME [--yes]" ;; esac; done
IID="$(instance_id)"; [[ -n "${IID}" ]] || die "instance ${NAME} not found"
VOL="$(scratch_vol)"
if [[ -z "${VOL}" ]]; then log "${NAME} has no scratch volume."; exit 0; fi
STATE="$(vm_status)"
SIZE="$("${A[@]}" ec2 describe-volumes --volume-ids "${VOL}" --query 'Volumes[0].Size' --output text)"
case "${STATE}" in
  running) HOW="unmount it live (stopping ${NAME} first if it is busy), then " ;;
  stopped) HOW="" ;;
  *)       HOW="stop ${NAME} (${STATE}), then " ;;
esac
log "Will: ${HOW}detach and DELETE ${VOL} (${SIZE} GB). All data on it is lost; there is no snapshot."
((YES)) || { log "Not doing it: re-run with --yes."; exit 0; }

if [[ "${STATE}" == running ]]; then
  ssh -o BatchMode=yes "${NAME}" 'sudo umount /mnt/scratch 2>/dev/null || ! mountpoint -q /mnt/scratch' \
    || { log "could not unmount /mnt/scratch (busy?); stopping ${NAME} instead"; stop_vm; }
elif [[ "${STATE}" != stopped ]]; then
  stop_vm
fi
if [[ "$(vol_state "${VOL}")" == in-use ]]; then
  "${A[@]}" ec2 detach-volume --volume-id "${VOL}" >/dev/null \
    || log "detach reported an error; checking whether it went through..."
  poll 36 vol_is "${VOL}" available || die "${VOL} is still attached"
fi
"${A[@]}" ec2 delete-volume --volume-id "${VOL}" || log "delete reported an error; checking whether it went through..."
poll 36 vol_gone "${VOL}" || die "${VOL} still exists"
log "Scratch volume deleted."
