# my-workstation

A plugin for **Claude Code**, **Codex**, and **Antigravity CLI** that manages personal **developer workstations in AWS and GCP**:
create a cloud VM already set up for AI-assisted development, snapshot it as a reusable "seed", then
shelve, recreate, and destroy it, and add or remove scratch disks as you go.

You describe what you want in plain language; the plugin interviews you, runs the cloud and Ansible
scripts, and asks before anything destructive.

## What you can do

| Use case | Example prompt | Skill |
|---|---|---|
| Create a workstation on GCP | "Provision a Debian 13 workstation on GCP called `dev1` in project `my-project` with Claude Code." | `provision-vm` |
| Create a workstation on AWS | "Provision an AWS workstation called `dev1` with Claude Code." | `provision-vm` |
| Create one with a remote desktop (AWS only) | "Provision an AWS workstation `gui1` with a GNOME desktop and NICE DCV." | `provision-vm` |
| Save the VM as a seed snapshot | "Take a seed snapshot of `dev1`." | `vm-lifecycle` |
| Refresh the seed after changing the VM | "Update the seed of `dev1` from its current disk." | `vm-lifecycle` |
| Add working space | "Add a 200 GB scratch disk to `dev1`." | `vm-lifecycle` |
| Remove working space | "Remove the scratch disk from `dev1`." | `vm-lifecycle` |
| Stop paying for the VM but keep it | "Shelve `dev1`: refresh the seed and delete the VM." | `vm-lifecycle` |
| Bring a shelved VM back | "Recreate `dev1` from its seed." | `vm-lifecycle` |
| Delete everything for a VM | "Destroy `dev1` completely, including its seed." | `vm-lifecycle` |

`vm-lifecycle` creates and deletes billed resources, so Claude Code only runs it when you ask for it
(for example `/my-workstation:vm-lifecycle dev1 add scratch 200`).

### Typical flow

1. **Once per project:** `provision-vm` creates and bootstraps the VM. Log in and configure it by hand
   (rclone, sign-ins for Claude and Codex, git clones). Then take the **seed snapshot** with `vm-lifecycle`.
2. **Whenever you work:** add a scratch disk for big data, remove it when done, and refresh the seed
   after you change the VM.
3. **When idle:** shelve the VM (only the seed snapshot is billed) and recreate it later in about 2–3 minutes.
4. **When finished:** destroy the VM, its disks, and its seed.

## What the plugin does

**`provision-vm`** asks for provider, name, location, base image (Debian 13 or Ubuntu 24.04), optional
GUI, optional apps, and SSH key. It then creates the network rule, identity, and VM, runs the Ansible
role, and records the VM in `~/.config/station-vm/<name>.env` plus an `ssh <name>` alias.

On every VM you get: an `aidev` user with passwordless sudo, zsh + oh-my-zsh, `uv`, GitHub CLI, `rclone`,
`ddclient`, **Codex CLI (always)**, Claude Code CLI (optional), and a bucket-mount tool (Mountpoint for S3 on
AWS, `gcsfuse` on GCP) with a commented-out `/etc/fstab` line ready to uncomment. AWS only, with GUI: GNOME,
NICE DCV, Chrome, and optionally Claude Desktop and ChatGPT Desktop.

**`vm-lifecycle`** works from the VM name. The seed is one snapshot of the root disk (a snapshot on GCP,
an AMI on AWS) and is replaced only after the new one is ready. Scratch disks can be attached and removed
while the VM runs.

If the machine type you chose is not available in the zone, the plugin offers similar types
(same vCPU, similar memory) and asks you to pick one.

## Defaults and safety

- **Region:** Oregon by default (AWS `us-west-2`, GCP `us-west1-b`). Other regions only when you ask.
- **Confirmation:** the plugin shows a plan and asks before it creates or deletes anything.
  Destructive scripts do nothing without `--yes`.
- **Scratch disks are never backed up.** Removing one deletes its data.
- **The VM's own identity** can read and write buckets, read secrets, and start or stop instances. It
  cannot create or delete instances or change IAM, networking, or firewalls.
- Firewall and security-group rules admit only your current public IP.
- The public IP changes on every stop and start; the scripts refresh your `ssh` alias.

## Requirements

On the machine where you run the plugin: the `aws` CLI (authenticated) for AWS, the `gcloud` CLI
(authenticated, with the Compute Engine API enabled) for GCP, `ansible` (`uv tool install ansible`),
`python3`, `curl`, and an SSH key (default `~/.ssh/id_ed25519`). On AWS you also need an existing EC2 key
pair that matches that key.

## Install

Claude Code:

```
/plugin install my-workstation --marketplace sloppycoder/my-workstation
```

Codex CLI (run once from any directory):

```bash
codex plugin marketplace add sloppycoder/my-workstation
codex plugin add my-workstation@my-workstation
```

This repo is both the plugin and a single-plugin marketplace, defined in
`.agents/plugins/marketplace.json`. In `my-workstation@my-workstation`, the first name is the plugin
and the second is the marketplace. Installation makes the plugin available to your user across repos.
Start a fresh Codex session in any repo after installing.

Check that it is installed and enabled:

```bash
codex plugin list --marketplace my-workstation
```

In Codex, type `$` and select a skill from autocomplete, or browse with `/skills`. For example:

```text
$my-workstation:provision-vm create a GCP VM named dev1
$my-workstation:vm-lifecycle dev1 seed
```

See the [Codex plugin documentation](https://developers.openai.com/plugins/build/plugins) for marketplace setup.

Antigravity CLI (`agy`):

```bash
git clone https://github.com/sloppycoder/my-workstation.git
agy plugin install ./my-workstation
agy plugin list
```

(Or if you already installed it in Claude Code, run `agy plugin import claude`.)

You can also use the skills directly from a clone, since `.claude/skills` and `.agents/skills` point at `skills/`.

## Configuration

Per-VM settings live outside the repo in `~/.config/station-vm/<name>.env` (written for you at the end of
provisioning). An optional `~/.config/station-vm/defaults.env` supplies your usual project, zone, region and
key. Copy and edit the files in [`examples/`](./examples/) to create them by hand.

## Status

Tested end to end on 2026-11-01 on both clouds (Debian 13, no GUI): provisioning, seed, scratch, shelve,
recreate, destroy, and mounting a bucket through each fstab example. Codex CLI installation from GitHub
was verified on 2026-11-02: version 0.2.0 installed and enabled, with both skills available after restart.
**Not yet tested:** the AWS GUI/NICE DCV path and Ubuntu images.

More detail is in [AGENTS.md](./AGENTS.md) and the `SKILL.md` file of each skill.

## License

MIT
