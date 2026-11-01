# AGENTS

Instructions for coding agents (Claude Code, Codex, ...) working in this repo.

## Purpose

`my-workstation` is a plugin (Claude Code and Codex) with two skills for
personal cloud dev VMs on **AWS** and **GCP**: `provision-vm` creates a VM and
bootstraps it, `vm-lifecycle` manages its seed snapshot and scratch disk. The repo
tracks no VMs: each VM's settings live in `~/.config/station-vm/<name>.env` (see
`examples/`), so don't write per-VM detail (ids, IPs, IAM dumps) into this file.

## Layout

```
.claude-plugin/  plugin.json, marketplace.json     (Claude Code)
.codex-plugin/   plugin.json                       (Codex)
.agents/         plugins/marketplace.json (Codex), skills -> ../skills
.claude/skills -> ../skills                        (in-repo use of the skills)
lib/             common.sh, update_ssh_config.py   (shared by all scripts)
skills/provision-vm/    SKILL.md, scripts/{aws,gcp}/, scripts/*.sh, runtime/ansible/
skills/vm-lifecycle/    SKILL.md, scripts/{aws,gcp}/
examples/        *.env.example: reference copies of ~/.config/station-vm/*.env
```

SKILL.md files are the source of truth for procedure and gotchas; read them
before changing scripts. Both skills are intentionally portable: plain-chat
interview, scripts that print `KEY=value` and take `--flags`.

## Conventions

- **Same script names, flags and output for `aws/` and `gcp/`.** If you add or
  change an action for one provider, do the other too (or say it's missing).
- Scripts source `lib/common.sh` via a `pwd -P` path, so they work through the
  `.claude/skills` and `.agents/skills` symlinks.
- Per-VM settings live **outside the repo** in `~/.config/station-vm/<name>.env`
  (written by `provision-vm/scripts/register.sh`); never commit project ids, keys
  or tokens.
- Optional `~/.config/station-vm/defaults.env` supplies user-wide defaults
  (interview proposals, `SEED_PREFIX`, `SNAPSHOT_LOCATION`); per-VM files override it.
- `create_vm.sh` exits **5** when the machine type is unavailable; the skill then
  runs `similar_types.sh` and asks the user to pick another (see the SKILL.md files).
- Destructive lifecycle scripts print a plan and need `--yes`. Never pass `--yes`
  without the user's explicit go-ahead; creating/deleting cloud resources costs money.
- Cloud CLI calls that a proxy may drop are `cmd || log ...` followed by `poll`.
- Linux bootstrap is Ansible (`skills/provision-vm/runtime/ansible/`, entrypoint
  `setup`; install with `uv tool install ansible` — needs `ansible.posix`). GUI tasks
  live only in `tasks/gui.yml`, imported when `enable_gui` and `cloud_provider=aws`.
- Codex CLI is installed by a direct ssh command, never an Ansible task (its
  installer hangs under `become`).
- Every VM gets the same identity (AWS `ai-workstation-role`, GCP `ai-workstation`
  service account). It deliberately cannot create/delete instances or touch
  IAM/network; widening that is the user's decision.

## Testing

No live test suite. Check changes with `bash -n`, `ansible-playbook --syntax-check`,
`claude plugin validate .`, and read-only cloud calls; real runs need a throwaway VM
that you delete afterwards. See "Status" in each SKILL.md for what is untested.
