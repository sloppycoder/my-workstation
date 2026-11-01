# Shared by the AWS vm-lifecycle scripts (sourced, not run).
# Every script is `script.sh NAME [args]`; NAME selects ~/.config/station-vm/NAME.env
# (written by provision-vm's register.sh). Needed there: REGION, SUBNET_ID,
# SECURITY_GROUP_ID, KEY_NAME, INSTANCE_TYPE (create_vm.sh only), SSH_USER, SSH_KEY.
# The instance is found by its Name tag, so its id may change across recreate.
#
# An AWS CLI call or wait may be dropped by a proxy although the operation proceeds.
# So every mutating command is written `cmd || log ...` and followed by `poll`,
# which checks the real end state.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need aws

SCRATCH_DEV=/dev/sdf

init() {  # init NAME
  NAME="${1:-}"; [[ -n "${NAME}" ]] || die "usage: $(basename "$0") NAME ..."
  load_instance "${NAME}"
  [[ "${PROVIDER:-}" == aws ]] || die "${NAME} is not an aws instance"
  : "${REGION:?REGION missing in config}"
  A=(aws --region "${REGION}")
}

# id of the live (not terminated) instance named NAME, or empty
instance_id() {
  "${A[@]}" ec2 describe-instances --filters "Name=tag:Name,Values=${NAME}" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text | awk '{print $1}'
}
vm_status() { [[ -n "${IID:-}" ]] && "${A[@]}" ec2 describe-instances --instance-ids "${IID}" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || true; }
vm_ip() { "${A[@]}" ec2 describe-instances --instance-ids "${IID}" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text; }
vm_az() { "${A[@]}" ec2 describe-instances --instance-ids "${IID}" --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text; }
vm_status_ok() { [[ "$("${A[@]}" ec2 describe-instance-status --instance-ids "${IID}" \
  --query 'InstanceStatuses[0].InstanceStatus.Status' --output text 2>/dev/null)" == ok ]]; }
has_status() { [[ "$(vm_status)" == "$1" ]]; }     # has_status running|stopped|...

scratch_vol() {   # id of the scratch volume (tag Name=NAME-scratch), or empty
  "${A[@]}" ec2 describe-volumes --filters "Name=tag:Name,Values=${NAME}-scratch" "Name=status,Values=creating,available,in-use" \
    --query 'Volumes[0].VolumeId' --output text | sed 's/^None$//'
}
vol_state() { "${A[@]}" ec2 describe-volumes --volume-ids "$1" --query 'Volumes[0].State' --output text 2>/dev/null || true; }
vol_is() { [[ "$(vol_state "$1")" == "$2" ]]; }
vol_gone() { [[ -z "$(vol_state "$1")" || "$(vol_state "$1")" == deleted ]]; }

# seed AMIs for this VM, newest first (ids; available ones only with "ready").
# Tag station-vm-seed=NAME.
seeds() {
  local f=("Name=tag:station-vm-seed,Values=${NAME}"); [[ "${1:-}" == ready ]] && f+=("Name=state,Values=available")
  "${A[@]}" ec2 describe-images --owners self --filters "${f[@]}" \
    --query 'sort_by(Images,&CreationDate)[::-1].ImageId' --output text | tr '\t' '\n' | grep . || true
}
ami_state() { "${A[@]}" ec2 describe-images --image-ids "$1" --query 'Images[0].State' --output text 2>/dev/null || true; }
ami_available() { [[ "$(ami_state "$1")" == available ]]; }
delete_ami() {  # deregister an AMI and delete its snapshots
  local ami="$1" snaps s
  snaps="$("${A[@]}" ec2 describe-images --image-ids "${ami}" --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text)"
  "${A[@]}" ec2 deregister-image --image-id "${ami}" || { log "could not deregister ${ami}"; return 1; }
  for s in ${snaps}; do [[ "${s}" == None ]] || "${A[@]}" ec2 delete-snapshot --snapshot-id "${s}" || log "could not delete ${s}"; done
}

stop_vm() {
  log "Stopping ${NAME}..."
  "${A[@]}" ec2 stop-instances --instance-ids "${IID}" >/dev/null || log "stop reported an error; checking whether it went through..."
  poll 120 has_status stopped || die "${NAME} did not stop"
}
start_vm() {
  log "Starting ${NAME}..."
  "${A[@]}" ec2 start-instances --instance-ids "${IID}" >/dev/null || log "start reported an error; checking whether it went through..."
  poll 60 has_status running || die "${NAME} did not start"
  refresh_ssh "${NAME}" "$(vm_ip)"
}
