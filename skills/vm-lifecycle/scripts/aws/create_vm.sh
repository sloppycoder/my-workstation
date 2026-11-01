#!/usr/bin/env bash
# Create the VM from its seed AMI and point the ssh alias at it. Root disk only;
# use add_scratch.sh for working space.
# usage: create_vm.sh NAME [--instance-type TYPE] [--ami AMI_ID]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; shift || true
TYPE="${INSTANCE_TYPE:-t3.large}" AMI=""
while [[ $# -gt 0 ]]; do case "$1" in
  --instance-type) TYPE="$2"; shift 2 ;; --ami) AMI="$2"; shift 2 ;;
  *) die "usage: create_vm.sh NAME [--instance-type TYPE] [--ami AMI_ID]" ;; esac; done
IID="$(instance_id)"; [[ -z "${IID}" ]] || die "instance ${NAME} already exists (${IID})"
[[ -n "${AMI}" ]] || AMI="$(seeds ready | head -1)"
[[ -n "${AMI}" ]] || die "no seed AMI for ${NAME}; run shelve_vm.sh on a configured VM first"
: "${SUBNET_ID:?SUBNET_ID missing in config}" "${SECURITY_GROUP_ID:?SECURITY_GROUP_ID missing in config}" "${KEY_NAME:?KEY_NAME missing in config}"

# Your public IP may have changed since the VM was last up: refresh the SG rules.
NET="$(dirname "${BASH_SOURCE[0]}")/../../../provision-vm/scripts/aws/ensure_network.sh"
GUI_ARG=(); if [[ "${GUI:-0}" == 1 ]]; then GUI_ARG=(--gui); fi
if [[ -x "${NET}" ]]; then "${NET}" --region "${REGION}" --name "${NAME}" --subnet-id "${SUBNET_ID}" ${GUI_ARG[@]+"${GUI_ARG[@]}"} >/dev/null
else log "WARNING: ensure_network.sh not found; security group source IP not refreshed"; fi

log "Creating ${NAME} (${TYPE}) from ${AMI}..."
ERR="$(mktemp)"; trap 'rm -f "${ERR}"' EXIT
IID="$("${A[@]}" ec2 run-instances --image-id "${AMI}" --instance-type "${TYPE}" --key-name "${KEY_NAME}" \
  --iam-instance-profile "Name=${PROFILE_NAME:-ai-workstation-role}" \
  --network-interfaces "[{\"DeviceIndex\":0,\"SubnetId\":\"${SUBNET_ID}\",\"Groups\":[\"${SECURITY_GROUP_ID}\"],\"AssociatePublicIpAddress\":true}]" \
  --tag-specifications "[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"${NAME}\"},{\"Key\":\"ManagedBy\",\"Value\":\"my-workstation\"}]}]" \
  --query 'Instances[0].InstanceId' --output text 2>"${ERR}")" \
  || { cat "${ERR}" >&2; ! type_unavailable_p "${ERR}" || exit_type_unavailable "${TYPE}"
       log "run-instances reported an error; checking whether it went through..."; IID=""; }
found() { IID="$(instance_id)"; [[ -n "${IID}" ]]; }
[[ -n "${IID}" ]] || poll 12 found || die "instance ${NAME} was not created"
poll 120 has_status running || die "${NAME} (${IID}) is not running"
poll 120 vm_status_ok || die "${NAME} (${IID}) did not pass status checks"
refresh_ssh "${NAME}" "$(vm_ip)"
log "${NAME} is up (${IID}): ssh ${NAME}   (no scratch disk yet: add_scratch.sh ${NAME})"
