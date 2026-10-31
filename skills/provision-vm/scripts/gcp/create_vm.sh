#!/usr/bin/env bash
# Create the GCE VM (public ephemeral IP) and wait until it is RUNNING.
# usage: create_vm.sh --project P --zone Z --name N --image-project IP --image-family IF
#          --machine-type T --volume-gb G --pubkey-file F --service-account SA [--boot-user admin]
# prints: INSTANCE_ID PUBLIC_IP
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need gcloud
PROJECT="" ZONE="" NAME="" IMGP="" IMGF="" TYPE="" GB="" PUB="" SA="" BOOT_USER=admin
while [[ $# -gt 0 ]]; do case "$1" in
  --project) PROJECT="$2"; shift 2 ;; --zone) ZONE="$2"; shift 2 ;; --name) NAME="$2"; shift 2 ;;
  --image-project) IMGP="$2"; shift 2 ;; --image-family) IMGF="$2"; shift 2 ;;
  --machine-type) TYPE="$2"; shift 2 ;; --volume-gb) GB="$2"; shift 2 ;; --pubkey-file) PUB="$2"; shift 2 ;;
  --service-account) SA="$2"; shift 2 ;; --boot-user) BOOT_USER="$2"; shift 2 ;; *) die "unknown flag $1" ;; esac; done
for v in PROJECT ZONE NAME IMGP IMGF TYPE GB PUB SA; do [[ -n "${!v}" ]] || die "missing --$(echo "${v}" | tr 'A-Z_' 'a-z-')"; done
[[ -f "${PUB}" ]] || die "public key file ${PUB} not found"
GC=(--project="${PROJECT}" --zone="${ZONE}")
status() { gcloud compute instances describe "${NAME}" "${GC[@]}" --format='value(status)' 2>/dev/null || true; }
running() { [[ "$(status)" == RUNNING ]]; }
[[ -z "$(status)" ]] || die "instance ${NAME} already exists"

KEY="$(cut -d' ' -f1,2 "${PUB}")"
ERR="$(mktemp)"; trap 'rm -f "${ERR}"' EXIT
gcloud compute instances create "${NAME}" "${GC[@]}" --machine-type="${TYPE}" \
  --image-family="${IMGF}" --image-project="${IMGP}" \
  --boot-disk-size="${GB}GB" --boot-disk-type=pd-balanced \
  --network-interface=network=default,subnet=default,network-tier=PREMIUM \
  --service-account="${SA}" --scopes=cloud-platform --tags="${NAME}" \
  --labels=managed-by=my-workstation \
  --metadata="ssh-keys=${BOOT_USER}:${KEY}" >/dev/null 2>"${ERR}" \
  || { cat "${ERR}" >&2; ! type_unavailable_p "${ERR}" || exit_type_unavailable "${TYPE}"
       log "create reported an error; checking whether it went through..."; }
poll 36 running || die "instance ${NAME} is not RUNNING"
IP="$(gcloud compute instances describe "${NAME}" "${GC[@]}" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
kv INSTANCE_ID "${NAME}"; kv PUBLIC_IP "${IP}"
