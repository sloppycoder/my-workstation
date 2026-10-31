#!/usr/bin/env bash
# Resolve the newest official AMI.
# usage: resolve_image.sh --region R --os debian13|ubuntu2404
# prints: IMAGE_ID ROOT_DEVICE BOOT_USER
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need aws
REGION="" OS=""
while [[ $# -gt 0 ]]; do case "$1" in
  --region) REGION="$2"; shift 2 ;; --os) OS="$2"; shift 2 ;;
  *) die "usage: resolve_image.sh --region R --os debian13|ubuntu2404" ;; esac; done
[[ -n "${REGION}" && -n "${OS}" ]] || die "usage: resolve_image.sh --region R --os debian13|ubuntu2404"
case "${OS}" in
  debian13)   OWNER=136693071363; FILTER='debian-13-amd64-*'; BOOT_USER=admin ;;
  ubuntu2404) OWNER=099720109477; FILTER='ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*'; BOOT_USER=ubuntu ;;
  *) die "unknown --os '${OS}' (debian13|ubuntu2404)" ;;
esac
read -r IMAGE_ID ROOT_DEVICE < <(aws ec2 describe-images --region "${REGION}" --owners "${OWNER}" \
  --filters "Name=name,Values=${FILTER}" "Name=architecture,Values=x86_64" \
            "Name=state,Values=available" "Name=virtualization-type,Values=hvm" \
  --query 'reverse(sort_by(Images, &CreationDate))[0].[ImageId,RootDeviceName]' --output text)
[[ -n "${IMAGE_ID}" && "${IMAGE_ID}" != "None" ]] || die "no ${OS} AMI found in ${REGION}"
kv IMAGE_ID "${IMAGE_ID}"; kv ROOT_DEVICE "${ROOT_DEVICE}"; kv BOOT_USER "${BOOT_USER}"
