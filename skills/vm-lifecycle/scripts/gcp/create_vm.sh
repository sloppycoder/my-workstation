#!/usr/bin/env bash
# Create the VM from its seed snapshot (made by shelve_vm.sh) and point the ssh
# alias at it. Boot disk only; use add_scratch.sh for working space.
# usage: create_vm.sh NAME [--machine-type TYPE] [--snapshot SEED]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; shift || true
TYPE="${MACHINE_TYPE:-e2-standard-2}" SEED=""
while [[ $# -gt 0 ]]; do case "$1" in
  --machine-type) TYPE="$2"; shift 2 ;; --snapshot) SEED="$2"; shift 2 ;;
  *) die "usage: create_vm.sh NAME [--machine-type TYPE] [--snapshot SEED]" ;; esac; done
[[ -z "$(vm_status)" ]] || die "instance ${NAME} already exists"
[[ -n "${SEED}" ]] || SEED="$(seeds ready | head -1)"
[[ -n "${SEED}" ]] || die "no READY seed snapshot for ${NAME}; run shelve_vm.sh on a configured VM first"
: "${SERVICE_ACCOUNT:?SERVICE_ACCOUNT missing in config}"

# Your public IP may have changed since the VM was last up: refresh the firewall rule.
FW="$(dirname "${BASH_SOURCE[0]}")/../../../provision-workstation/scripts/gcp/ensure_network.sh"
if [[ -x "${FW}" ]]; then "${FW}" --project "${PROJECT}" --name "${NAME}" >/dev/null; else log "WARNING: ensure_network.sh not found; firewall source IP not refreshed"; fi

log "Creating ${NAME} (${TYPE}) from ${SEED}..."
gcloud compute disks create "${NAME}" "${GC[@]}" --source-snapshot="${SEED}" --type=pd-balanced \
  || log "create reported an error; checking whether it went through..."
poll 36 has_status disks "${NAME}" READY || die "boot disk ${NAME} did not become READY"
gcloud compute instances create "${NAME}" "${GC[@]}" --machine-type="${TYPE}" \
  --disk="name=${NAME},boot=yes,auto-delete=yes,device-name=${NAME}" \
  --network-interface=network=default,subnet=default,network-tier=PREMIUM \
  --service-account="${SERVICE_ACCOUNT}" --scopes=cloud-platform --tags="${NAME}" \
  --labels=managed-by=my-workstation || log "create reported an error; checking whether it went through..."
poll 36 has_status instances "${NAME}" RUNNING || die "instance ${NAME} is not RUNNING"
refresh_ssh "${NAME}" "$(vm_ip)"
log "${NAME} is up: ssh ${NAME}   (no scratch disk yet: add_scratch.sh ${NAME})"
