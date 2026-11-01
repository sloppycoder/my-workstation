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
plugin.json      Agent Plugins 1.0.0 manifest         (Codex, Antigravity)
.claude-plugin/  plugin.json, marketplace.json        (Claude Code)
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

## Releasing / version bumps

Claude Code installs this plugin through the separate marketplace repo at
`../marketplace` (GitHub `vino9net`, catalog `.claude-plugin/marketplace.json`, remote
entry `sloppycoder/my-workstation`). Whenever you bump the version, check that
everything affected is updated, in both repos:

- This repo: `version` in **both** `plugin.json` and
  `.claude-plugin/plugin.json` (keep them equal); `description` kept in sync across
  both plugin.json files and `.claude-plugin/marketplace.json` / `.agents/plugins/marketplace.json`.
- `../marketplace`: the `my-workstation` entry in `.claude-plugin/marketplace.json`
  (it pins no version, but its `description` must match what the plugin now does),
  the my-workstation row in `README.md`, and the my-workstation section in `CLAUDE.md`.
  Bump the marketplace's own `version` if its catalog changed.
- If skills, scripts or flags were added/removed, update the SKILL.md files and `README.md`
  here first; they are what the marketplace summary is derived from.
- Run `claude plugin validate .` here, then commit and push this repo **before**
  the marketplace (it installs from GitHub, so unpushed changes are invisible).
  Don't commit or push either repo without the user's go-ahead.
