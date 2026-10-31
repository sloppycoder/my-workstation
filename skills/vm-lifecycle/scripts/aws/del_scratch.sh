#!/usr/bin/env bash
# Delete the scratch volume. ALL DATA ON IT IS LOST (never imaged).
# Default: unmount over ssh and detach while the VM keeps running. If busy, or with
# --stop, the VM is stopped first (and stays stopped).
# usage: del_scratch.sh NAME [--stop] [--yes]     (without --yes: prints the plan only)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; shift || true
STOP=0 YES=0
while [[ $# -gt 0 ]]; do case "$1" in --stop) STOP=1; shift ;; --yes) YES=1; shift ;;
  *) die "usage: del_scratch.sh NAME [--stop] [--yes]" ;; esac; done
IID="$(instance_id)"; [[ -n "${IID}" ]] || die "instance ${NAME} not found"
VOL="$(scratch_vol)"
if [[ -z "${VOL}" ]]; then log "${NAME} has no scratch volume."; exit 0; fi
STATE="$(vm_state)"
if ((STOP)) || [[ "${STATE}" != running ]]; then HOW="stop ${NAME} (${STATE}), then"; else HOW="unmount it live, then"; fi
log "Will: ${HOW} detach and DELETE ${VOL}. All data on it is lost; there is no snapshot."
((YES)) || { log "Not doing it: re-run with --yes."; exit 0; }

if [[ "${STATE}" == running ]] && ((!STOP)); then
  ssh -o BatchMode=yes "${NAME}" 'sudo umount /mnt/scratch 2>/dev/null || ! mountpoint -q /mnt/scratch' \
    || die "could not unmount /mnt/scratch (busy?). Stop whatever uses it, or re-run with --stop"
elif [[ "${STATE}" != stopped ]]; then
  stop_vm
fi
if [[ "$(vol_state "${VOL}")" == in-use ]]; then
  "${A[@]}" ec2 detach-volume --volume-id "${VOL}" >/dev/null
  poll 36 vol_is "${VOL}" available || die "${VOL} is still attached"
fi
"${A[@]}" ec2 delete-volume --volume-id "${VOL}"
poll 36 vol_gone "${VOL}" || die "${VOL} still exists"
log "Scratch volume deleted."
