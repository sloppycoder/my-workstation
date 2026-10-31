#!/usr/bin/env bash
# Resolve the official GCE image family.
# usage: resolve_image.sh --os debian13|ubuntu2404
# prints: IMAGE_PROJECT IMAGE_FAMILY IMAGE_NAME BOOT_USER
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need gcloud
OS=""
while [[ $# -gt 0 ]]; do case "$1" in --os) OS="$2"; shift 2 ;; *) die "usage: resolve_image.sh --os debian13|ubuntu2404" ;; esac; done
case "${OS}" in
  debian13)   PROJECT=debian-cloud;    FAMILY=debian-13 ;;
  ubuntu2404) PROJECT=ubuntu-os-cloud; FAMILY=ubuntu-2404-lts-amd64 ;;
  *) die "usage: resolve_image.sh --os debian13|ubuntu2404" ;;
esac
NAME="$(gcloud compute images describe-from-family "${FAMILY}" --project="${PROJECT}" --format='value(name)')"
[[ -n "${NAME}" ]] || die "no image in family ${FAMILY}"
# The login user is whatever we put in the ssh-keys metadata (see create_vm.sh).
kv IMAGE_PROJECT "${PROJECT}"; kv IMAGE_FAMILY "${FAMILY}"; kv IMAGE_NAME "${NAME}"; kv BOOT_USER admin
