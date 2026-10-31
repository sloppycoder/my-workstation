# Shared helpers for the my-workstation scripts (sourced, not run).
#
# Conventions for every script that uses this file:
#   - flags are `--key value`; results go to stdout as KEY=value lines;
#     progress and errors go to stderr (so `eval "$(script ...)"` is safe)
#   - cloud CLI calls that can be dropped by a proxy are written
#     `cmd || log "..."` and followed by `poll` on the real end state
#   - per-instance settings live in ~/.config/station-vm/<name>.env

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_DIR="${STATION_VM_CONFIG_DIR:-${HOME}/.config/station-vm}"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo ">> $*" >&2; }
kv() { printf '%s=%s\n' "$1" "$2"; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH"; }

poll() {  # poll <tries> <command...>   (5 s apart)
  local n="$1" i; shift
  for ((i = 0; i < n; i++)); do "$@" && return 0; sleep 5; done
  return 1
}

my_ip() { curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]'; }

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=8)

wait_ssh() {  # wait_ssh USER HOST KEYFILE [TRIES]
  local user="$1" host="$2" key="$3" tries="${4:-60}" i
  log "Waiting for ssh ${user}@${host}..."
  for ((i = 0; i < tries; i++)); do
    ssh "${SSH_OPTS[@]}" -i "${key}" "${user}@${host}" true </dev/null 2>/dev/null && return 0
    sleep 5
  done
  die "ssh ${user}@${host} did not come up"
}

# ---- per-instance config -------------------------------------------------

load_instance() {  # load_instance NAME  -> exports the variables in NAME.env
  local f="${CONFIG_DIR}/$1.env"
  [[ -f "${f}" ]] || die "no config for instance '$1' (${f}); provision it first"
  set -a; . "${f}"; set +a
}

save_instance() {  # save_instance NAME KEY=VALUE...   (rewrites the file)
  local name="$1"; shift
  mkdir -p "${CONFIG_DIR}"
  printf '%s\n' "$@" > "${CONFIG_DIR}/${name}.env"
  chmod 600 "${CONFIG_DIR}/${name}.env"
}

# ---- ssh alias -----------------------------------------------------------

# Point the ~/.ssh/config alias NAME at IP (adding the block if missing), drop
# stale host keys, and wait for ssh. Needed after every create and every start
# because the public IP is ephemeral.  Uses SSH_USER and SSH_KEY from the
# instance config.
refresh_ssh() {  # refresh_ssh NAME IP
  local name="$1" ip="$2" old h
  old="$(ssh -G "${name}" 2>/dev/null | awk '$1 == "hostname" {print $2}')"
  python3 -I "${LIB_DIR}/update_ssh_config.py" "${name}" "${ip}" \
    --user "${SSH_USER:-aidev}" ${SSH_KEY:+--identity "${SSH_KEY}"} >&2
  for h in "${name}" "${ip}" "${old}"; do
    if [[ -n "${h}" ]]; then ssh-keygen -R "${h}" >/dev/null 2>&1 || true; fi
  done
  wait_ssh "${SSH_USER:-aidev}" "${ip}" "${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
}
