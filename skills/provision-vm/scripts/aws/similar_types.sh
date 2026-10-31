#!/usr/bin/env bash
# List current-generation instance types offered in the region's AZ (or all AZs) with
# the same vCPU count as the wanted one and similar memory (+/-25%).
# Use after create_vm.sh exits 5 (type unavailable).
# usage: similar_types.sh --region R --vcpus N --mem-gb M [--az AZ]
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need aws
REGION="" CPUS="" MEM="" AZ=""
while [[ $# -gt 0 ]]; do case "$1" in
  --region) REGION="$2"; shift 2 ;; --vcpus) CPUS="$2"; shift 2 ;; --mem-gb) MEM="$2"; shift 2 ;; --az) AZ="$2"; shift 2 ;;
  *) die "usage: similar_types.sh --region R --vcpus N --mem-gb M [--az AZ]" ;; esac; done
[[ -n "${REGION}" && -n "${CPUS}" && -n "${MEM}" ]] || die "--region, --vcpus and --mem-gb are required"
LO=$((MEM * 1024 * 3 / 4)); HI=$((MEM * 1024 * 5 / 4))
OFFERED="$(mktemp)"; trap 'rm -f "${OFFERED}"' EXIT
aws ec2 describe-instance-type-offerings --region "${REGION}" --location-type availability-zone \
  ${AZ:+--filters "Name=location,Values=${AZ}"} --query 'InstanceTypeOfferings[].InstanceType' --output text \
  | tr '\t' '\n' | sort -u > "${OFFERED}"
aws ec2 describe-instance-types --region "${REGION}" \
  --filters "Name=vcpu-info.default-vcpus,Values=${CPUS}" "Name=current-generation,Values=true" \
            "Name=processor-info.supported-architecture,Values=x86_64" \
  --query 'InstanceTypes[].[InstanceType,MemoryInfo.SizeInMiB]' --output text \
  | awk -v lo="${LO}" -v hi="${HI}" '$2>=lo && $2<=hi {print $1, $2}' | sort -k2,2n \
  | while read -r t m; do grep -qx "${t}" "${OFFERED}" && printf '%s  %s vCPU  %.0f GB\n' "${t}" "${CPUS}" "$((m / 1024))"; done
