#!/usr/bin/env bash
# Remove EVERYTHING for this VM: the instance (and root disk), the scratch volume,
# every seed AMI + snapshot, and the local config. Irreversible.
# usage: destroy_vm.sh NAME [--yes]     (without --yes: lists what would be deleted)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; shift || true
[[ "${1:-}" == "--yes" ]] && YES=1 || YES=0
IID="$(instance_id)"; VOL="$(scratch_vol)"; SEEDS="$(seeds)"
log "Will DELETE: instance ${NAME} (${IID:-absent}); scratch volume ${VOL:-none}; seed AMIs: $(echo ${SEEDS:-none}); security group ${SECURITY_GROUP_ID:-none}; ssh alias; ${CONFIG_DIR}/${NAME}.env"
log "This cannot be undone."
((YES)) || { log "Not doing it: re-run with --yes."; exit 0; }
if [[ -n "${IID}" ]]; then
  "${A[@]}" ec2 terminate-instances --instance-ids "${IID}" >/dev/null
  "${A[@]}" ec2 wait instance-terminated --instance-ids "${IID}"
fi
if [[ -n "${VOL}" ]]; then poll 36 vol_is "${VOL}" available || true; "${A[@]}" ec2 delete-volume --volume-id "${VOL}" || log "could not delete ${VOL}"; fi
for a in ${SEEDS}; do delete_ami "${a}"; done
if [[ -n "${SECURITY_GROUP_ID:-}" ]]; then   # best effort: the SG may still be referenced
  "${A[@]}" ec2 delete-security-group --group-id "${SECURITY_GROUP_ID}" 2>/dev/null || log "could not delete security group ${SECURITY_GROUP_ID} (in use?)"
fi
forget_ssh "${NAME}"
rm -f "${CONFIG_DIR}/${NAME}.env"
log "Destroyed ${NAME} (the shared ai-workstation-role is kept)."
