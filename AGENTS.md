# AGENTS

Instructions for coding agents (Claude Code, Codex, ...) working in this repo.

## Purpose

`my-workstation` is a plugin (Claude Code and Codex) with two skills for
personal cloud dev VMs on **AWS** and **GCP**, plus a lightweight index of VMs
actually provisioned with it. Per-instance detail (IAM, packages, access info)
lives one file per instance under `docs/instances/`, not here — keep this file
from growing as more VMs are provisioned.

## Layout

```
.claude-plugin/  plugin.json, marketplace.json     (Claude Code)
.codex-plugin/   plugin.json                       (Codex)
.agents/         plugins/marketplace.json (Codex), skills -> ../skills
.claude/skills -> ../skills                        (in-repo use of the skills)
lib/             common.sh, update_ssh_config.py   (shared by all scripts)
skills/provision-vm/    SKILL.md, scripts/{aws,gcp}/, scripts/*.sh, runtime/ansible/
skills/vm-lifecycle/    SKILL.md, scripts/{aws,gcp}/
docs/instances/  one file per provisioned VM
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

## Provisioned instances

Detail for each instance lives in its own file under `docs/instances/` — this
index just tracks what exists and where.

| Instance | Region | Purpose | Status |
|---|---|---|---|
| [aidev-workstation](./docs/instances/aidev-workstation.md) | ap-northeast-1 (Tokyo) | GUI + CLI AI dev workstation; also hosts the `gphoto` S3 mount | Active |

Retired: a standalone `gphoto` EC2 instance in us-west-2 (never part of this
skill) was decommissioned 2026-08-19 — its role was absorbed into
aidev-workstation. See that instance's doc for the full history and the
backup snapshot ID.
