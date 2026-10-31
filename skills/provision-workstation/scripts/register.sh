#!/usr/bin/env bash
# Record a provisioned VM so the vm-lifecycle scripts can find it, and point an
# ~/.ssh/config alias (named after the VM) at it.
# usage: register.sh --name N --provider aws|gcp --ip IP --key PRIVATE_KEY [KEY=VALUE ...]
#   extra KEY=VALUE pairs (REGION, PROJECT, ZONE, INSTANCE_ID, ...) are stored verbatim
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../lib/common.sh"
NAME="" PROVIDER="" IP="" KEY="" EXTRA=()
while [[ $# -gt 0 ]]; do case "$1" in
  --name) NAME="$2"; shift 2 ;; --provider) PROVIDER="$2"; shift 2 ;; --ip) IP="$2"; shift 2 ;;
  --key) KEY="$2"; shift 2 ;; *=*) EXTRA+=("$1"); shift ;; *) die "unknown arg $1" ;; esac; done
for v in NAME PROVIDER IP KEY; do [[ -n "${!v}" ]] || die "missing --$(echo "${v}" | tr 'A-Z' 'a-z')"; done
KEY="$(cd "$(dirname "${KEY/#\~/${HOME}}")" && pwd -P)/$(basename "${KEY}")"
save_instance "${NAME}" "NAME=${NAME}" "PROVIDER=${PROVIDER}" "SSH_USER=aidev" "SSH_KEY=${KEY}" ${EXTRA[@]+"${EXTRA[@]}"}
log "Saved ${CONFIG_DIR}/${NAME}.env"
SSH_USER=aidev SSH_KEY="${KEY}" refresh_ssh "${NAME}" "${IP}"
log "ssh ${NAME} works"
