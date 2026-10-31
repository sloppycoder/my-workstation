#!/usr/bin/env bash
# Find a VPC + public subnet and make a security group that admits only your
# current public IP (22/80/443, plus 8443 tcp+udp with --gui).
# usage: ensure_network.sh --region R --name N [--gui] [--vpc-id V] [--subnet-id S]
# prints: VPC_ID SUBNET_ID SECURITY_GROUP_ID MY_IP
# exit 3: several VPCs and none chosen (table on stderr; re-run with --vpc-id)
# exit 4: no public subnet in the VPC (re-run with --subnet-id, or fix the VPC)
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../../lib/common.sh"
need aws
REGION="" NAME="" GUI=0 VPC_ID="" SUBNET_ID=""
while [[ $# -gt 0 ]]; do case "$1" in
  --region) REGION="$2"; shift 2 ;; --name) NAME="$2"; shift 2 ;; --gui) GUI=1; shift ;;
  --vpc-id) VPC_ID="$2"; shift 2 ;; --subnet-id) SUBNET_ID="$2"; shift 2 ;;
  *) die "usage: ensure_network.sh --region R --name N [--gui] [--vpc-id V] [--subnet-id S]" ;; esac; done
[[ -n "${REGION}" && -n "${NAME}" ]] || die "--region and --name are required"
A=(aws ec2 --region "${REGION}")

if [[ -z "${VPC_ID}" ]]; then
  VPC_ID="$("${A[@]}" describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
  if [[ "${VPC_ID}" == "None" ]]; then   # no default VPC: normal for some accounts
    COUNT="$("${A[@]}" describe-vpcs --query 'length(Vpcs)' --output text)"
    if [[ "${COUNT}" == "1" ]]; then
      VPC_ID="$("${A[@]}" describe-vpcs --query 'Vpcs[0].VpcId' --output text)"
      log "No default VPC; using the only VPC, ${VPC_ID}"
    else
      "${A[@]}" describe-vpcs --query 'Vpcs[].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table >&2
      echo "ERROR: ${COUNT} VPCs and no default; re-run with --vpc-id" >&2; exit 3
    fi
  fi
fi

# A subnet is public if its route table (explicit association, else the VPC's main
# table) sends 0.0.0.0/0 to an internet gateway. MapPublicIpOnLaunch is irrelevant:
# create_vm.sh asks for a public IP explicitly.
if [[ -z "${SUBNET_ID}" ]]; then
  TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
  "${A[@]}" describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" --output json > "${TMP}/rt.json"
  "${A[@]}" describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --output json > "${TMP}/sn.json"
  SUBNET_ID="$(python3 -I - "${TMP}/rt.json" "${TMP}/sn.json" <<'PY'
import json, sys
rts = json.load(open(sys.argv[1]))["RouteTables"]
subnets = json.load(open(sys.argv[2]))["Subnets"]
def public(table):
    return any(r.get("DestinationCidrBlock") == "0.0.0.0/0" and str(r.get("GatewayId", "")).startswith("igw-")
               for r in table["Routes"])
main = [t for t in rts if any(a.get("Main") for a in t["Associations"])]
for s in sorted(subnets, key=lambda s: (s["AvailabilityZone"], s["SubnetId"])):
    own = [t for t in rts if any(a.get("SubnetId") == s["SubnetId"] for a in t["Associations"])]
    if any(public(t) for t in (own or main)):
        print(s["SubnetId"]); break
PY
)"
  if [[ -z "${SUBNET_ID}" ]]; then
    "${A[@]}" describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'Subnets[].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]' --output table >&2
    echo "ERROR: no subnet in ${VPC_ID} routes to an internet gateway; a private subnet would be unreachable. Re-run with --subnet-id" >&2
    exit 4
  fi
fi

IP="$(my_ip)"
SG="$("${A[@]}" describe-security-groups --filters "Name=group-name,Values=${NAME}-sg" "Name=vpc-id,Values=${VPC_ID}" \
  --query 'SecurityGroups[0].GroupId' --output text)"
if [[ "${SG}" == "None" ]]; then
  log "Creating security group ${NAME}-sg"
  SG="$("${A[@]}" create-security-group --group-name "${NAME}-sg" --description "${NAME} workstation" \
    --vpc-id "${VPC_ID}" --query GroupId --output text)"
fi

RULES=("tcp 22" "tcp 80" "tcp 443")
((GUI)) && RULES+=("tcp 8443" "udp 8443")
for r in "${RULES[@]}"; do
  read -r proto port <<<"${r}"
  have="$("${A[@]}" describe-security-groups --group-ids "${SG}" --query \
    "SecurityGroups[0].IpPermissions[?IpProtocol=='${proto}' && FromPort==\`${port}\`].IpRanges[].CidrIp" --output text)"
  ok=0
  for cidr in ${have}; do   # drop rules left over from an older IP
    if [[ "${cidr}" == "${IP}/32" ]]; then ok=1
    else log "Revoking stale ${proto}/${port} from ${cidr}"
      "${A[@]}" revoke-security-group-ingress --group-id "${SG}" --protocol "${proto}" --port "${port}" --cidr "${cidr}" >/dev/null
    fi
  done
  ((ok)) || "${A[@]}" authorize-security-group-ingress --group-id "${SG}" --protocol "${proto}" --port "${port}" --cidr "${IP}/32" >/dev/null
done
kv VPC_ID "${VPC_ID}"; kv SUBNET_ID "${SUBNET_ID}"; kv SECURITY_GROUP_ID "${SG}"; kv MY_IP "${IP}"
