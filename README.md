# my-workstation

Personal AI dev workstations on AWS and GCP, as a plugin for Claude Code and Codex.

| Skill | Does |
|---|---|
| `provision-vm` | Interview → create a VM on AWS or GCP → Ansible bootstrap (zsh, uv, gh, rclone, bucket mount, ddclient, Claude Code / Codex; optional GNOME + NICE DCV on AWS). |
| `vm-lifecycle` | Seed snapshot of the root disk, recreate from it, add/remove a scratch disk, shelve, destroy. |

Install (Claude Code): `/plugin install my-workstation --marketplace sloppycoder/station-vm`
(becomes `sloppycoder/my-workstation` if the repo is renamed).
Codex: the marketplace is `.agents/plugins/marketplace.json`; see the Codex plugin docs.

Typical flow: run `provision-vm` once per project → log in and configure the VM →
`vm-lifecycle` to take the seed snapshot → then add/remove scratch disks and
refresh the seed as needed. Details: [AGENTS.md](./AGENTS.md), the SKILL.md files,
and [docs/instances/](./docs/instances/).
