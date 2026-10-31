#!/usr/bin/env bash
# Make (first time) or replace the VM's seed AMI from its current root disk.
# The VM is stopped for a consistent image, then restarted -- or, with --delete,
# terminated with its root disk (an attached scratch volume is NOT imaged and is
# deleted too). The old seed is removed only after the new one is available, and the
# VM is terminated only after that.
# usage: shelve_vm.sh NAME [--delete] [--yes]     (without --yes: prints the plan only)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; shift || true
DELETE=0 YES=0
while [[ $# -gt 0 ]]; do case "$1" in --delete) DELETE=1; shift ;; --yes) YES=1; shift ;;
  *) die "usage: shelve_vm.sh NAME [--delete] [--yes]" ;; esac; done
IID="$(instance_id)"; [[ -n "${IID}" ]] || die "instance ${NAME} not found"
STATE="$(vm_state)"; SCRATCH="$(scratch_vol)"; OLD="$(seeds)"
AMI_NAME="${SEED_PREFIX:-${NAME}}-seed-$(date -u +%Y%m%d-%H%M%S)"
log "Will: stop ${NAME} (${IID}, ${STATE}); create AMI ${AMI_NAME} from its root disk;${OLD:+ delete old seed(s) $(echo ${OLD});}"
if ((DELETE)); then log "     then TERMINATE ${NAME}${SCRATCH:+ and delete scratch volume ${SCRATCH} (data lost)}."
else log "     then start ${NAME} again (scratch volume, if any, stays attached and is not imaged)."; fi
((YES)) || { log "Not doing it: re-run with --yes."; exit 0; }

[[ "${STATE}" == stopped ]] || stop_vm
# NoDevice keeps the scratch volume out of the image
AMI="$("${A[@]}" ec2 create-image --instance-id "${IID}" --name "${AMI_NAME}" \
  --block-device-mappings "[{\"DeviceName\":\"${SCRATCH_DEV}\",\"NoDevice\":\"\"}]" \
  --tag-specifications "ResourceType=image,Tags=[{Key=station-vm-seed,Value=${NAME}}]" \
                       "ResourceType=snapshot,Tags=[{Key=station-vm-seed,Value=${NAME}}]" \
  --query ImageId --output text)"
log "Creating ${AMI} (${AMI_NAME})..."
poll 240 ami_available "${AMI}" || die "${AMI} is not available yet; old seed kept and ${NAME} untouched"
for a in ${OLD}; do log "Deleting old seed ${a}"; delete_ami "${a}"; done
if ((DELETE)); then
  log "${AMI} is available. Terminating ${NAME}..."
  "${A[@]}" ec2 terminate-instances --instance-ids "${IID}" >/dev/null
  "${A[@]}" ec2 wait instance-terminated --instance-ids "${IID}"
  if [[ -n "${SCRATCH}" ]]; then poll 36 vol_is "${SCRATCH}" available || true; "${A[@]}" ec2 delete-volume --volume-id "${SCRATCH}" || log "could not delete ${SCRATCH}"; fi
  log "Shelved. Bring it back with: create_vm.sh ${NAME}"
else
  start_vm
  log "Seed updated: ${AMI}. ${NAME} is running again."
fi
