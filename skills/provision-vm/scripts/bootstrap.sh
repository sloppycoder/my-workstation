#!/usr/bin/env bash
# Linux-side bootstrap: run the Ansible role, then (optionally) install Codex CLI
# over a direct ssh command (its installer hangs under Ansible's become).
# usage: bootstrap.sh --host IP --user BOOT_USER --key PRIVATE_KEY --provider aws|gcp
#          [--gui] [--claude-code] [--claude-desktop] [--chatgpt-desktop]
# Codex CLI is always installed (not optional).
#          [-- extra ansible-playbook args, e.g. -e ddclient_zone=...]
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../lib/common.sh"
ANSIBLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../runtime/ansible"
HOST="" USER_="" KEY="" PROVIDER="" GUI=false CC=false CD=false CGPT=false EXTRA=()
while [[ $# -gt 0 ]]; do case "$1" in
  --host) HOST="$2"; shift 2 ;; --user) USER_="$2"; shift 2 ;; --key) KEY="$2"; shift 2 ;;
  --provider) PROVIDER="$2"; shift 2 ;; --gui) GUI=true; shift ;; --claude-code) CC=true; shift ;;
  --claude-desktop) CD=true; shift ;; --chatgpt-desktop) CGPT=true; shift ;;
  --) shift; EXTRA=("$@"); break ;; *) die "unknown flag $1" ;; esac; done
for v in HOST USER_ KEY PROVIDER; do [[ -n "${!v}" ]] || die "missing --$(echo "${v%_}" | tr 'A-Z' 'a-z')"; done
[[ "${PROVIDER}" == aws || "${PROVIDER}" == gcp ]] || die "--provider must be aws or gcp"
need ansible-playbook
[[ -f "${KEY}.pub" ]] || die "${KEY}.pub not found (needed for the aidev user's authorized_keys)"

"${ANSIBLE_DIR}/setup" "${HOST}" "${USER_}" --private-key "${KEY}" \
  -e "cloud_provider=${PROVIDER}" -e "new_user_name=aidev" -e "new_user_sudoer=true" \
  -e "authorized_pub_key=$(cat "${KEY}.pub")" \
  -e "enable_gui=${GUI}" -e "install_claude_code=${CC}" \
  -e "install_claude_desktop=${CD}" -e "install_chatgpt_desktop=${CGPT}" ${EXTRA[@]+"${EXTRA[@]}"}

log "Installing Codex CLI for aidev (direct ssh; '< /dev/null' is required)"
ssh "${SSH_OPTS[@]}" -i "${KEY}" "aidev@${HOST}" 'curl -fsSL https://chatgpt.com/codex/install.sh | sh' < /dev/null
log "Bootstrap finished"
