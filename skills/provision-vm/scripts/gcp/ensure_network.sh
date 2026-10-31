#!/usr/bin/env bash
# Firewall rule on the default network admitting only your current public IP
# (tcp 22/80/443) to VMs tagged with --name. No GUI ports: DCV is AWS-only.
# usage: ensure_network.sh --project P --name N
# prints: NETWORK_TAG MY_IP
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need gcloud
PROJECT="" NAME=""
while [[ $# -gt 0 ]]; do case "$1" in
  --project) PROJECT="$2"; shift 2 ;; --name) NAME="$2"; shift 2 ;;
  *) die "usage: ensure_network.sh --project P --name N" ;; esac; done
[[ -n "${PROJECT}" && -n "${NAME}" ]] || die "--project and --name are required"
gcloud compute networks describe default --project="${PROJECT}" >/dev/null 2>&1 \
  || die "project ${PROJECT} has no 'default' network; create one or pass a different network (not supported yet)"
IP="$(my_ip)"
RULE="${NAME}-allow-me"
if gcloud compute firewall-rules describe "${RULE}" --project="${PROJECT}" >/dev/null 2>&1; then
  log "Updating ${RULE} source range to ${IP}/32"
  gcloud compute firewall-rules update "${RULE}" --project="${PROJECT}" --source-ranges="${IP}/32" >/dev/null
else
  log "Creating firewall rule ${RULE}"
  gcloud compute firewall-rules create "${RULE}" --project="${PROJECT}" --network=default \
    --direction=INGRESS --action=ALLOW --rules=tcp:22,tcp:80,tcp:443 \
    --source-ranges="${IP}/32" --target-tags="${NAME}" >/dev/null
fi
kv NETWORK_TAG "${NAME}"; kv MY_IP "${IP}"
