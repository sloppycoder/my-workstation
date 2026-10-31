#!/usr/bin/env bash
# Launch the EC2 instance and wait until it is running and status-ok.
# usage: create_vm.sh --region R --name N --image-id I --root-device D --instance-type T
#          --volume-gb G --key-name K --subnet-id S --sg-id SG [--profile P]
# prints: INSTANCE_ID PUBLIC_IP
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need aws
REGION="" NAME="" IMAGE="" ROOT="" TYPE="" GB="" KEY="" SUBNET="" SG="" PROFILE=ai-workstation-role
while [[ $# -gt 0 ]]; do case "$1" in
  --region) REGION="$2"; shift 2 ;; --name) NAME="$2"; shift 2 ;; --image-id) IMAGE="$2"; shift 2 ;;
  --root-device) ROOT="$2"; shift 2 ;; --instance-type) TYPE="$2"; shift 2 ;; --volume-gb) GB="$2"; shift 2 ;;
  --key-name) KEY="$2"; shift 2 ;; --subnet-id) SUBNET="$2"; shift 2 ;; --sg-id) SG="$2"; shift 2 ;;
  --profile) PROFILE="$2"; shift 2 ;; *) die "unknown flag $1" ;; esac; done
for v in REGION NAME IMAGE ROOT TYPE GB KEY SUBNET SG; do [[ -n "${!v}" ]] || die "missing --${v,,}"; done

EXISTING="$(aws ec2 describe-instances --region "${REGION}" \
  --filters "Name=tag:Name,Values=${NAME}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
[[ -z "${EXISTING}" ]] || die "an instance named ${NAME} already exists (${EXISTING})"

ID="$(aws ec2 run-instances --region "${REGION}" \
  --image-id "${IMAGE}" --instance-type "${TYPE}" --key-name "${KEY}" \
  --iam-instance-profile "Name=${PROFILE}" \
  --block-device-mappings "[{\"DeviceName\":\"${ROOT}\",\"Ebs\":{\"VolumeSize\":${GB},\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
  --network-interfaces "[{\"DeviceIndex\":0,\"SubnetId\":\"${SUBNET}\",\"Groups\":[\"${SG}\"],\"AssociatePublicIpAddress\":true}]" \
  --tag-specifications "[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"${NAME}\"},{\"Key\":\"ManagedBy\",\"Value\":\"my-workstation\"}]}]" \
  --query 'Instances[0].InstanceId' --output text)"
log "Launched ${ID}; waiting for running + status ok"
aws ec2 wait instance-running --region "${REGION}" --instance-ids "${ID}"
aws ec2 wait instance-status-ok --region "${REGION}" --instance-ids "${ID}"
IP="$(aws ec2 describe-instances --region "${REGION}" --instance-ids "${ID}" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
kv INSTANCE_ID "${ID}"; kv PUBLIC_IP "${IP}"
