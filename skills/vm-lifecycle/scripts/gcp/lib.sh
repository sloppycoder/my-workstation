# Shared by the GCP vm-lifecycle scripts (sourced, not run).
# Every script is called `script.sh NAME [args]`; NAME selects
# ~/.config/station-vm/NAME.env (written by provision-vm's register.sh).
#
# gcloud's long "wait for operation" call is sometimes dropped by a proxy
# (ProxyError) although the operation proceeds. So every mutating command is
# written `cmd || log ...` and followed by `poll`, which checks the real end state.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need gcloud

init() {  # init NAME
  NAME="${1:-}"; [[ -n "${NAME}" ]] || die "usage: $(basename "$0") NAME ..."
  load_instance "${NAME}"
  [[ "${PROVIDER:-}" == gcp ]] || die "${NAME} is not a gcp instance"
  : "${PROJECT:?PROJECT missing in config}" "${ZONE:?ZONE missing in config}"
  GC=(--project="${PROJECT}" --zone="${ZONE}")
}

status_of() { gcloud compute "$1" describe "$2" "${GC[@]}" --format='value(status)' 2>/dev/null || true; }
vm_status() { status_of instances "${NAME}"; }
has_status() { [[ "$(status_of "$1" "$2")" == "$3" ]]; }     # has_status instances|disks NAME STATUS
gone() { [[ -z "$(status_of "$1" "$2")" ]]; }                # gone instances|disks NAME
snapshot_ready() {
  [[ "$(gcloud compute snapshots describe "$1" --project="${PROJECT}" --format='value(status)' 2>/dev/null || true)" == READY ]]
}
# name of the attached boot disk, or of the disk attached with device name "scratch"
attached_disk() {  # attached_disk boot|scratch
  gcloud compute instances describe "${NAME}" "${GC[@]}" --format=json 2>/dev/null \
    | python3 -I -c 'import json, sys
want = sys.argv[1]
for d in json.load(sys.stdin).get("disks", []):
    if (want == "boot" and d.get("boot")) or d.get("deviceName") == want:
        print(d["source"].rsplit("/", 1)[1])' "$1" || true
}
scratch_is() { [[ "$(attached_disk scratch)" == "$1" ]]; }
scratch_none() { [[ -z "$(attached_disk scratch)" ]]; }
vm_ip() { gcloud compute instances describe "${NAME}" "${GC[@]}" --format='value(networkInterfaces[0].accessConfigs[0].natIP)'; }
# seed snapshots for this VM, newest first (READY only with "ready")
seeds() {
  local f="labels.station-vm-seed=${NAME}"; [[ "${1:-}" == ready ]] && f+=" AND status=READY"
  gcloud compute snapshots list --project="${PROJECT}" --filter="${f}" --sort-by=~creationTimestamp --format='value(name)' 2>/dev/null
}
stop_vm() {
  log "Stopping ${NAME}..."
  gcloud compute instances stop "${NAME}" "${GC[@]}" || log "stop reported an error; checking whether it went through..."
  poll 60 has_status instances "${NAME}" TERMINATED || die "${NAME} did not stop"
}
start_vm() {
  log "Starting ${NAME}..."
  gcloud compute instances start "${NAME}" "${GC[@]}" || log "start reported an error; checking whether it went through..."
  poll 36 has_status instances "${NAME}" RUNNING || die "${NAME} did not start"
  refresh_ssh "${NAME}" "$(vm_ip)"
}
