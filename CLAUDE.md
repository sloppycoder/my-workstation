# CLAUDE

## Purpose

This repo hosts `provision-ai-workstation`, an interview-driven Claude Code
skill for standing up AWS EC2 AI dev workstations, plus a lightweight index of
instances actually provisioned with it. Full per-instance detail (IAM
policies, installed packages, access info, etc.) lives one file per instance
under `docs/instances/`, not in this file — keeps this file from growing
without bound as more VMs get provisioned. See **Provisioned instances**
below for the index and links.

## Running the skill

The skill lives at
[skills/provision-ai-workstation/SKILL.md](./skills/provision-ai-workstation/SKILL.md)
(symlinked from `.claude/skills/`, so it's directly invocable). That file is
the source of truth for the exact procedure and gotchas — this section is
just the shape of it:

- **Always interviews fresh, every run**: instance name, AWS region, base
  image (Debian 13 preferred / Ubuntu 24.04 LTS alternative, both official
  AWS AMIs), GUI desktop + NICE DCV toggle, and which of Claude Code CLI /
  Codex CLI / Claude Desktop / ChatGPT Desktop to install. There is no
  stored provider-defaults file — nothing is cached or assumed between runs.
- **AWS-side orchestration is run as live commands, not a wrapped script.**
  AMI lookup, VPC/subnet discovery, security group sync, the IAM instance
  profile, `run-instances`, and waiting for SSH are executed one at a time by
  whoever runs the skill, so edge cases (no default VPC — true for this
  account in `ap-northeast-1`, a security group that already exists, a
  changed public IP) get handled in the moment instead of failing inside a
  black box.
- **Every instance gets the same IAM instance profile**, `ai-workstation-role`
  (account-wide, reused across all instances, GUI or not): DCV license S3
  read, EC2 start/stop/reboot/status in any region, S3
  read/write/delete/list on any bucket (delete + abort-multipart granted
  specifically so Mountpoint for S3 can support `--allow-delete` and
  writes), Secrets Manager read + discovery in any region, and EBS
  volume/snapshot management. No `TerminateInstances`, `RunInstances`, or
  anything touching IAM/VPC/security groups — see SKILL.md §2.4 for the
  exact policy.
- **Linux-side bootstrap is a proper Ansible role**, at
  `skills/provision-ai-workstation/runtime/ansible/`, run via its `setup`
  entrypoint after SSH is up. It's deterministic and doesn't benefit from
  live improvisation, unlike the AWS orchestration above. If `ansible-playbook`
  isn't already available on the provisioning machine, the preferred install
  method is `uv tool install ansible` (not apt/pip/brew) — the role uses the
  `ansible.posix.authorized_key` module, which needs the full `ansible`
  package rather than just `ansible-core`; `uv tool install` keeps it
  isolated rather than mixed into system Python.
- `rclone`, Mountpoint for S3 (`mount-s3`), and `ddclient` are installed
  **unconditionally** on every instance — not interview questions.
  `mount-s3` needs no credential setup (uses the instance role directly);
  `ddclient`'s `/etc/ddclient.conf` ships with dummy Cloudflare placeholder
  values (`zone=example.com`, etc.) that must be edited in before dynamic
  DNS actually does anything.
- **Codex CLI is installed via a direct SSH command after the Ansible run
  finishes, not as an Ansible task** — its installer hangs forever under
  Ansible's `become`, which allocates a pty that the installer's trailing
  interactive shell never gets EOF on.

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
