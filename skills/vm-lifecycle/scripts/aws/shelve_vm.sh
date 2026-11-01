#!/usr/bin/env bash
# Make (first time) or replace the VM's seed AMI from its current root disk.
# The VM is stopped for a consistent image and left stopped -- or, with --delete,
# terminated with its root disk (an attached scratch volume is NOT imaged and is
# deleted too). The old seed is removed only after the new one is available, and the
# VM is terminated only after that. It never starts the VM.
# usage: shelve_vm.sh NAME [--delete] [--yes]     (without --yes: prints the plan only)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; shift || true
DELETE=0 YES=0
while [[ $# -gt 0 ]]; do case "$1" in --delete) DELETE=1; shift ;; --yes) YES=1; shift ;;
  *) die "usage: shelve_vm.sh NAME [--delete] [--yes]" ;; esac; done
IID="$(instance_id)"; [[ -n "${IID}" ]] || die "instance ${NAME} not found"
STATE="$(vm_status)"; SCRATCH="$(scratch_vol)"; OLD="$(seeds)"
AMI_NAME="${SEED_PREFIX:-${NAME}}-seed-$(date -u +%Y%m%d-%H%M%S)"
log "Will: stop ${NAME} (${IID}, ${STATE}); create AMI ${AMI_NAME} from its root disk;${OLD:+ delete old seed(s) $(echo ${OLD});}"
if ((DELETE)); then log "     then TERMINATE ${NAME}${SCRATCH:+ and delete scratch volume ${SCRATCH} (data lost)}."
else log "     then leave ${NAME} stopped (scratch volume, if any, stays attached and is not imaged)."; fi
((YES)) || { log "Not doing it: re-run with --yes."; exit 0; }

[[ "${STATE}" == stopped ]] || stop_vm
# NoDevice keeps the scratch volume out of the image
ami_by_name() { "${A[@]}" ec2 describe-images --owners self --filters "Name=name,Values=${AMI_NAME}" \
  --query 'Images[0].ImageId' --output text 2>/dev/null | sed 's/^None$//'; }
AMI="$("${A[@]}" ec2 create-image --instance-id "${IID}" --name "${AMI_NAME}" \
  --block-device-mappings "[{\"DeviceName\":\"${SCRATCH_DEV}\",\"NoDevice\":\"\"}]" \
  --tag-specifications "ResourceType=image,Tags=[{Key=station-vm-seed,Value=${NAME}}]" \
                       "ResourceType=snapshot,Tags=[{Key=station-vm-seed,Value=${NAME}}]" \
  --query ImageId --output text)" || { log "create-image reported an error; checking whether it went through..."; AMI=""; }
ami_named() { [[ -n "$(ami_by_name)" ]]; }
if [[ -z "${AMI}" ]]; then poll 12 ami_named || true; AMI="$(ami_by_name)"; fi
[[ -n "${AMI}" ]] || die "no AMI named ${AMI_NAME} was created; ${NAME} is stopped and untouched"
log "Creating ${AMI} (${AMI_NAME})..."
poll 240 ami_available "${AMI}" || die "${AMI} is not available yet; old seed kept and ${NAME} untouched"
for a in ${OLD}; do log "Deleting old seed ${a}"; delete_ami "${a}" || log "could not delete ${a}"; done
if ((DELETE)); then
  log "${AMI} is available. Terminating ${NAME}..."
  "${A[@]}" ec2 terminate-instances --instance-ids "${IID}" >/dev/null \
    || log "terminate reported an error; checking whether it went through..."
  poll 120 has_status terminated || die "${NAME} is not terminated"
  if [[ -n "${SCRATCH}" ]]; then
    poll 36 vol_is "${SCRATCH}" available || true
    "${A[@]}" ec2 delete-volume --volume-id "${SCRATCH}" || log "delete-volume reported an error; checking whether it went through..."
    poll 12 vol_gone "${SCRATCH}" || log "could not delete ${SCRATCH}"
  fi
  log "Shelved. Bring it back with: create_vm.sh ${NAME}"
else
  log "Seed updated: ${AMI}. ${NAME} is stopped."
fi
