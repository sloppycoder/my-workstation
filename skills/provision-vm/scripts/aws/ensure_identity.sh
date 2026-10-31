#!/usr/bin/env bash
# Create (once, account-wide) the ai-workstation-role role + instance profile.
# Policies are in policies/*.json; see SKILL.md for what is deliberately NOT granted.
# usage: ensure_identity.sh
# prints: PROFILE_NAME
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need aws
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/policies"
ROLE=ai-workstation-role
NEW=0
if ! aws iam get-role --role-name "${ROLE}" >/dev/null 2>&1; then
  log "Creating role ${ROLE}"
  aws iam create-role --role-name "${ROLE}" --assume-role-policy-document "file://${HERE}/trust.json" >/dev/null
fi
for p in dcv-license-s3-read workstation-access; do   # put-role-policy is idempotent
  aws iam put-role-policy --role-name "${ROLE}" --policy-name "${p}" --policy-document "file://${HERE}/${p}.json"
done
if ! aws iam get-instance-profile --instance-profile-name "${ROLE}" >/dev/null 2>&1; then
  log "Creating instance profile ${ROLE}"
  aws iam create-instance-profile --instance-profile-name "${ROLE}" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "${ROLE}" --role-name "${ROLE}"
  NEW=1
fi
((NEW)) && { log "Waiting 10s for IAM propagation"; sleep 10; }
kv PROFILE_NAME "${ROLE}"
