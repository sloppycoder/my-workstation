#!/usr/bin/env bash
# List machine types available in a zone with the same vCPU count as the wanted one
# and similar memory (+/-25%), cheapest-looking first (E2/N2/N2D/N4/C3 families).
# Use after create_vm.sh exits 5 (type unavailable).
# usage: similar_types.sh --project P --zone Z --vcpus N --mem-gb M
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need gcloud
PROJECT="" ZONE="" CPUS="" MEM=""
while [[ $# -gt 0 ]]; do case "$1" in
  --project) PROJECT="$2"; shift 2 ;; --zone) ZONE="$2"; shift 2 ;; --vcpus) CPUS="$2"; shift 2 ;; --mem-gb) MEM="$2"; shift 2 ;;
  *) die "usage: similar_types.sh --project P --zone Z --vcpus N --mem-gb M" ;; esac; done
[[ -n "${PROJECT}" && -n "${ZONE}" && -n "${CPUS}" && -n "${MEM}" ]] || die "all of --project --zone --vcpus --mem-gb are required"
LO=$((MEM * 1024 * 3 / 4)); HI=$((MEM * 1024 * 5 / 4))
gcloud compute machine-types list --project="${PROJECT}" --zones="${ZONE}" \
  --filter="guestCpus=${CPUS} AND memoryMb>=${LO} AND memoryMb<=${HI}" --format=json \
  | python3 -I -c 'import json, re, sys
for t in sorted(json.load(sys.stdin), key=lambda t: (t["memoryMb"], t["name"])):
    if re.match(r"(e2|n2|n2d|n4|c3)-", t["name"]):
        print("%s  %s vCPU  %.0f GB" % (t["name"], t["guestCpus"], t["memoryMb"] / 1024))'
