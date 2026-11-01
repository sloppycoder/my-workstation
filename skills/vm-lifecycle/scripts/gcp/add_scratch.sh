#!/usr/bin/env bash
# Add a scratch disk: create, attach (live if the VM runs), format if blank,
# mount at /mnt/scratch. Starts the VM first if it is stopped. Never snapshotted.
# usage: add_scratch.sh NAME [GB]      (default 150)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
init "${1:-}"; SIZE="${2:-150}"
[[ "${SIZE}" =~ ^[0-9]+$ ]] && ((SIZE >= 10)) || die "usage: add_scratch.sh NAME [GB >= 10]"
DISK="${NAME}-scratch"
STATUS="$(vm_status)"
[[ -n "${STATUS}" ]] || die "instance ${NAME} not found"
[[ -z "$(attached_disk scratch)" ]] || die "${NAME} already has a scratch disk"
[[ -z "$(status_of disks "${DISK}")" ]] || die "disk ${DISK} already exists (not attached)"
[[ "${STATUS}" == RUNNING ]] || start_vm

log "Creating ${DISK} (${SIZE} GB) and attaching to ${NAME}..."
gcloud compute disks create "${DISK}" "${GC[@]}" --size="${SIZE}" --type=pd-balanced \
  --labels=managed-by=my-workstation \
  || log "create reported an error; checking whether it went through..."
poll 36 has_status disks "${DISK}" READY || die "${DISK} did not become READY"
gcloud compute instances attach-disk "${NAME}" "${GC[@]}" --disk="${DISK}" --device-name=scratch \
  || log "attach reported an error; checking whether it went through..."
poll 36 scratch_is "${DISK}" || die "${DISK} did not attach"

log "Formatting and mounting..."
ssh -o BatchMode=yes "${NAME}" 'sudo bash -s' <<'REMOTE'
set -euo pipefail
DEV=/dev/disk/by-id/google-scratch
for i in $(seq 1 30); do [ -e "$DEV" ] && break; sleep 1; done
[ -e "$DEV" ] || { echo "device $DEV did not appear" >&2; exit 1; }
blkid "$DEV" >/dev/null 2>&1 || mkfs.ext4 -q -F -m 0 "$DEV"
mkdir -p /mnt/scratch
grep -q '^/dev/disk/by-id/google-scratch ' /etc/fstab || \
  echo '/dev/disk/by-id/google-scratch /mnt/scratch ext4 defaults,nofail,x-systemd.device-timeout=5s 0 2' >> /etc/fstab
systemctl daemon-reload
mountpoint -q /mnt/scratch || mount /mnt/scratch
chmod 1777 /mnt/scratch
df -h /mnt/scratch | tail -1
REMOTE
log "Scratch disk ready: ${DISK} at /mnt/scratch"
