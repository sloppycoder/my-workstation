#!/usr/bin/env bash
# Remove EVERYTHING for this VM: the instance (and root disk), the scratch volume,
# every seed AMI + snapshot, and the local config. Irreversible.
# usage: destroy_vm.sh NAME [--yes]     (without --yes: lists what would be deleted)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; shift || true
[[ "${1:-}" == "--yes" ]] && YES=1 || YES=0
IID="$(instance_id)"; VOL="$(scratch_vol)"; SEEDS="$(seeds)"
log "Will DELETE: instance ${NAME} (${IID:-absent}); scratch volume ${VOL:-none}; seed AMIs: $(echo ${SEEDS:-none}); ${CONFIG_DIR}/${NAME}.env"
log "This cannot be undone."
((YES)) || { log "Not doing it: re-run with --yes."; exit 0; }
if [[ -n "${IID}" ]]; then
  "${A[@]}" ec2 terminate-instances --instance-ids "${IID}" >/dev/null
  "${A[@]}" ec2 wait instance-terminated --instance-ids "${IID}"
fi
if [[ -n "${VOL}" ]]; then poll 36 vol_is "${VOL}" available || true; "${A[@]}" ec2 delete-volume --volume-id "${VOL}" || log "could not delete ${VOL}"; fi
for a in ${SEEDS}; do delete_ami "${a}"; done
rm -f "${CONFIG_DIR}/${NAME}.env"
log "Destroyed ${NAME}. (A Host ${NAME} block may remain in ~/.ssh/config.)"
