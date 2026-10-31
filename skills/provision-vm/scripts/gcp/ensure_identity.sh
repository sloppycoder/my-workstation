#!/usr/bin/env bash
# Create (once per project) the ai-workstation service account: GCP's
# counterpart of the AWS ai-workstation-role. Grants Cloud Storage object
# read/write/delete, Secret Manager read, and a custom role for start/stop/
# reset + disk/snapshot handling. Deliberately NOT granted: creating or
# deleting instances, and anything touching IAM or the network.
# usage: ensure_identity.sh --project P
# prints: SERVICE_ACCOUNT
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need gcloud
PROJECT=""
while [[ $# -gt 0 ]]; do case "$1" in --project) PROJECT="$2"; shift 2 ;; *) die "usage: ensure_identity.sh --project P" ;; esac; done
[[ -n "${PROJECT}" ]] || die "--project is required"
SA_ID=ai-workstation
SA="${SA_ID}@${PROJECT}.iam.gserviceaccount.com"
ROLE=aiWorkstationOps
PERMS=compute.instances.get,compute.instances.list,compute.instances.start,compute.instances.stop,compute.instances.reset,compute.instances.attachDisk,compute.instances.detachDisk,compute.disks.create,compute.disks.delete,compute.disks.get,compute.disks.list,compute.disks.use,compute.disks.createSnapshot,compute.snapshots.create,compute.snapshots.delete,compute.snapshots.get,compute.snapshots.list,compute.snapshots.setLabels,compute.zones.get,compute.zones.list

NEW=0
if ! gcloud iam service-accounts describe "${SA}" --project="${PROJECT}" >/dev/null 2>&1; then
  log "Creating service account ${SA}"
  gcloud iam service-accounts create "${SA_ID}" --project="${PROJECT}" --display-name="AI workstation" >/dev/null
  NEW=1
fi
if gcloud iam roles describe "${ROLE}" --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud iam roles update "${ROLE}" --project="${PROJECT}" --permissions="${PERMS}" >/dev/null
else
  gcloud iam roles create "${ROLE}" --project="${PROJECT}" --title="AI workstation ops" --permissions="${PERMS}" >/dev/null
fi
for r in roles/storage.objectUser roles/secretmanager.secretAccessor roles/secretmanager.viewer "projects/${PROJECT}/roles/${ROLE}"; do
  gcloud projects add-iam-policy-binding "${PROJECT}" --member="serviceAccount:${SA}" --role="${r}" \
    --condition=None >/dev/null
done
((NEW)) && { log "Waiting 15s for IAM propagation"; sleep 15; }
kv SERVICE_ACCOUNT "${SA}"
