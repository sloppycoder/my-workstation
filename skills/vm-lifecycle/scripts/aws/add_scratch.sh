#!/usr/bin/env bash
# Add a scratch EBS volume: create (same AZ), attach live, format if blank, mount
# at /mnt/scratch. Starts the VM first if it is stopped. Never imaged/snapshotted.
# usage: add_scratch.sh NAME [GB]      (default 150)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; SIZE="${2:-150}"
[[ "${SIZE}" =~ ^[0-9]+$ ]] && ((SIZE >= 10)) || die "usage: add_scratch.sh NAME [GB >= 10]"
IID="$(instance_id)"; [[ -n "${IID}" ]] || die "instance ${NAME} not found"
[[ -z "$(scratch_vol)" ]] || die "${NAME} already has a scratch volume"
[[ "$(vm_status)" == running ]] || start_vm
AZ="$(vm_az)"
log "Creating ${SIZE} GB volume in ${AZ} and attaching to ${NAME}..."
VOL="$("${A[@]}" ec2 create-volume --availability-zone "${AZ}" --size "${SIZE}" --volume-type gp3 \
  --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${NAME}-scratch},{Key=ManagedBy,Value=my-workstation}]" \
  --query VolumeId --output text)" || { log "create reported an error; checking whether it went through..."; VOL=""; }
vol_found() { VOL="$(scratch_vol)"; [[ -n "${VOL}" ]]; }
[[ -n "${VOL}" ]] || poll 12 vol_found || die "volume ${NAME}-scratch was not created"
poll 36 vol_is "${VOL}" available || die "${VOL} did not become available"
"${A[@]}" ec2 attach-volume --volume-id "${VOL}" --instance-id "${IID}" --device "${SCRATCH_DEV}" >/dev/null \
  || log "attach reported an error; checking whether it went through..."
poll 36 vol_is "${VOL}" in-use || die "${VOL} did not attach"

log "Formatting and mounting..."
ssh -o BatchMode=yes "${NAME}" "sudo VOL=${VOL//-/} bash -s" <<'REMOTE'
set -euo pipefail
DEV=/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${VOL}
for i in $(seq 1 30); do [ -e "$DEV" ] && break; sleep 1; done
[ -e "$DEV" ] || { echo "device $DEV did not appear" >&2; exit 1; }
blkid "$DEV" >/dev/null 2>&1 || mkfs.ext4 -q -F -m 0 -L scratch "$DEV"
mkdir -p /mnt/scratch
grep -q '^LABEL=scratch ' /etc/fstab || \
  echo 'LABEL=scratch /mnt/scratch ext4 defaults,nofail,x-systemd.device-timeout=5s 0 2' >> /etc/fstab
systemctl daemon-reload
mountpoint -q /mnt/scratch || mount /mnt/scratch
chmod 1777 /mnt/scratch
df -h /mnt/scratch | tail -1
REMOTE
log "Scratch volume ready: ${VOL} at /mnt/scratch"
