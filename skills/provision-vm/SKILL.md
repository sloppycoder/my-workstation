---
name: provision-vm
description: Interview the user, then provision a cloud dev workstation on AWS (EC2) or GCP (Compute Engine) — optionally with a GNOME desktop + NICE DCV remote desktop (AWS only) with Codex CLI always installed plus a chosen subset of Claude Code CLI / Claude Desktop / ChatGPT Desktop — using the bundled per-provider scripts, then the bundled Ansible role for the Linux-side bootstrap.
---

# Provision Workstation

Provisions a fresh VM as a personal AI dev workstation on **AWS** or **GCP**.
Cloud-side work is done by small scripts, one set per provider with identical
flags and `KEY=value` output, so this procedure is the same for both. Claude
runs them one at a time, so unexpected states (no default VPC, several VPCs,
no public subnet, a changed public IP) are seen and handled in the moment —
the scripts exit with distinct codes for exactly those cases instead of guessing.
The Linux-side bootstrap is an Ansible role (`runtime/ansible/`).

`SKILL_DIR` below is this skill's directory. Scripts live in `$SKILL_DIR/scripts/`.
There is no stored defaults file; every run interviews fresh.

## 1. Interview (always ask, every run)

If `~/.config/station-vm/defaults.env` exists, read it first and propose its values
as the answers (`AWS_REGION`, `GCP_PROJECT`, `GCP_ZONE`, `SSH_KEY`, `IMAGE_OS`
= `debian13|ubuntu2404`, `ROOT_GB`, `MACHINE_TYPE`, `SEED_PREFIX`); the user can
accept or override each. Never write that file without being asked.

Ask in plain chat as **one numbered batch** with the defaults shown, so it works
in any agent (use a structured question tool only if one is available). If the
user's request already answers an item, don't re-ask it.

1. **Provider** — `aws` or `gcp`.
2. **Instance name** — free text. Used for the VM name, firewall/security group
   (`<name>-sg` / `<name>-allow-me`) and the `~/.ssh/config` alias.
3. **Location** — AWS: region (e.g. `ap-northeast-1`), no default. GCP: project
   id and zone (e.g. `us-west1-b`), no default.
4. **Base image** — Debian 13 (default) or Ubuntu 24.04 LTS; both official.
5. **GUI desktop** — **AWS only**, default **no**. Yes adds GNOME + NICE DCV.
   On GCP don't offer it; if the user asks, explain DCV is AWS-only.
6. **Components** (none preselected): Claude Code CLI, and — only with GUI —
   Claude Desktop, ChatGPT Desktop. **Codex CLI is always installed**; don't ask. If a desktop app is chosen
   without GUI, point out the conflict and ask; never drop it silently.
7. **SSH key** — AWS: name of an existing EC2 key pair (never created here) and
   its private key path. GCP: just the private key path; the matching `.pub` is
   put in instance metadata. Default path `~/.ssh/id_ed25519`.

Defaults unless overridden: AWS `m5.xlarge`/40 GB (GUI) or `t3.large`/20 GB;
GCP `e2-standard-2`/20 GB. New Linux user `aidev`, passwordless sudo.

Then show a **one-screen plan summary** and get explicit confirmation before
creating anything — this spends real money and creates account-level resources.

## 2. Procedure

Each script prints `KEY=value` lines on stdout (progress on stderr); capture
them, e.g. `eval "$($SKILL_DIR/scripts/aws/resolve_image.sh --region R --os debian13)"`.
Substitute `aws`/`gcp` for `$P` below. Flags are shown in each script's header.

1. **Image** — `scripts/$P/resolve_image.sh` (`--os debian13|ubuntu2404`; AWS also
   `--region`). Returns the image and `BOOT_USER` (AWS: `admin`/`ubuntu`; GCP: `admin`).
2. **Network** — `scripts/$P/ensure_network.sh`. Creates/updates the security group
   (AWS) or firewall rule (GCP), locked to your current public IP (`/32`): 22, 80,
   443, plus 8443 tcp+udp with `--gui` (AWS). Re-running after your IP changed
   replaces the stale rule rather than stacking another.
   - AWS exit **3** = several VPCs and no default: show the table it printed,
     ask the user, re-run with `--vpc-id`. Exit **4** = no public subnet: stop
     and ask (a private subnet would be unreachable; there is no bastion).
     No default VPC alone is normal — the script handles it.
3. **Identity** — `scripts/$P/ensure_identity.sh`. Reused account-wide (AWS
   `ai-workstation-role` instance profile; GCP `ai-workstation` service account).
   See §4 for what it grants and what it deliberately doesn't.
4. **Create** — `scripts/$P/create_vm.sh`. Waits until the VM is up and prints
   `INSTANCE_ID`, `PUBLIC_IP`. Refuses if a VM with that name exists.
   **Exit 5 = the machine/instance type is not available** in that zone (unknown
   there, unsupported, or out of capacity; the script prints
   `MACHINE_TYPE_UNAVAILABLE=<type>`). Don't retry the same type and don't give up:
   run `scripts/$P/similar_types.sh` (same vCPU, memory ±25%; GCP: `--project --zone
   --vcpus --mem-gb`, AWS: `--region --vcpus --mem-gb [--az]`), then **ask the user
   to pick**, offering the closest 2–3 with a recommendation. If they answer "any
   similar one", pick the closest match yourself (prefer the same family, then the
   cheapest) and say which you chose. Re-run `create_vm.sh` with the new type and
   use that type in step 6 (`register.sh`). Nothing is left behind on exit 5.
5. **Bootstrap** — `scripts/bootstrap.sh --host $PUBLIC_IP --user $BOOT_USER
   --key KEY --provider $P [--gui] [--claude-code] [--claude-desktop]
   [--chatgpt-desktop]`. Runs the Ansible role, then always installs Codex over a direct
   ssh command (its installer hangs under Ansible's `become`). First wait for ssh
   with `ssh -o StrictHostKeyChecking=no -i KEY $BOOT_USER@$PUBLIC_IP true`
   (retry ~every 5 s for a few minutes). If `ansible-playbook` is missing:
   `uv tool install ansible` (the full package — the role needs `ansible.posix`).
6. **Register** — `scripts/register.sh --name N --provider $P --ip $PUBLIC_IP
   --key KEY KEY=VALUE...`. Writes `~/.config/station-vm/<name>.env` (read by the
   `vm-lifecycle` skill, which needs these values to recreate the VM) and points the
   `ssh <name>` alias at the VM. Pass — AWS: `REGION SUBNET_ID SECURITY_GROUP_ID
   KEY_NAME INSTANCE_TYPE PROFILE_NAME` (+ `GUI=1` if GUI); GCP: `PROJECT ZONE
   SERVICE_ACCOUNT MACHINE_TYPE`.
7. **GUI only: reboot once and verify.** `ssh <name> sudo reboot`, wait for ssh,
   then check `gdm dcvserver dcv-console-session` are `active`. ssh returns
   ~30–40 s before `dcv-console-session` settles (it waits on `dcvserver`), so
   retry the check for ~60 s before declaring a failure.

### What the Ansible role does

Base (always): packages (incl. `ddclient`) → `aidev` user → `uv` → oh-my-zsh →
GitHub CLI → rclone (official installer; distro package is stale) → bucket mount
(AWS: Mountpoint for S3 `mount-s3`, GPG-verified; GCP: `gcsfuse`; both use the VM's
own identity, no credentials to set up) → `ddclient` → Claude Code CLI (if chosen).
GUI (`tasks/gui.yml`, only when `enable_gui` **and** `cloud_provider=aws`): `sudo`
group membership (needed for GNOME/polkit prompts), GNOME + Xdummy + Chrome,
NICE DCV, Claude Desktop, ChatGPT Desktop. The role asserts GUI ⇒ AWS and
desktop apps ⇒ GUI.

`ddclient` ships with dummy Cloudflare values (`zone=example.com`, …) because the
VM has no static IP; dynamic DNS does nothing until real values are edited into
`/etc/ddclient.conf` and `sudo systemctl restart ddclient`. They can be passed at
provision time after `--` (`-e ddclient_zone=… -e ddclient_hostname=…
-e ddclient_cloudflare_api_token=…`) if the user volunteers them; don't ask.

## 3. Report back

- `ssh <name>` (alias, user `aidev`) and the bootstrap-user command.
- GUI: `https://<ip>:8443` (self-signed cert), user `aidev`, password in
  `/root/aidev_dcv_password.txt` on the VM (`sudo cat`, or `sudo passwd aidev`).
- Which components were installed; Claude Code, Codex, and the desktop apps all
  need an **interactive sign-in on first use**.
- The public IP is ephemeral (changes on every stop/start); `ddclient` is
  placeholder-only (above).
- Next step: configure the VM by hand (rclone, sign-ins, git clones), then use
  the `vm-lifecycle` skill to take the seed snapshot.

## 4. Identity: what is granted

Both providers grant the same capabilities to the workstation itself:

- Object storage read/write/**delete**/list on any bucket (delete and
  abort-multipart exist so Mountpoint for S3 / gcsfuse can write and `rm`).
- Secrets read + discovery (Secrets Manager / Secret Manager).
- Start/stop/reboot/describe instances, and disk + snapshot management.
- AWS only: `s3:GetObject` on `dcv-license.*` — **without it `dcvserver` won't
  start**; the profile must be attached before the DCV install.

**Deliberately not granted**: terminate/run (create/delete) instances, and
anything touching IAM, VPC/network, or security groups/firewalls. Treat any
widening as the user's explicit decision. AWS policies:
`scripts/aws/policies/*.json`. GCP: roles in `scripts/gcp/ensure_identity.sh`
(custom role `aiWorkstationOps`). After creating a *new* AWS instance profile the
script waits 10 s (GCP: 15 s) for IAM propagation.

## 5. Known gotchas (already handled; keep them handled)

1. NICE DCV has no Debian build; the Ubuntu 24.04 x86_64 build runs on Debian 13
   but is unsupported by AWS — flag it as a caveat when Debian + GUI is chosen.
2. DCV's license check needs the instance profile attached *before* `dcvserver` starts.
3. `automatic-console-session` in `dcv.conf` is unreliable; the role uses a
   systemd oneshot (`dcv-console-session.service`).
4. `gnome-core` + `gdm3` can leave `display-manager.service` stale; the role reasserts it.
5. `pulseaudio-utils` is needed for DCV microphone redirection (in the GUI task list).
6. polkit only honours real `sudo` group membership, not `sudoers.d`; a fresh login
   is needed for it to apply.
7. Codex's installer hangs under Ansible `become` — always a direct ssh step, with
   `< /dev/null`.
8. gcloud's long "wait for operation" call is sometimes dropped by a proxy although
   the operation succeeds; GCP scripts tolerate the error and poll the real state.
   "…reported an error; checking whether it went through" is normal.
9. Untested paths (written but not yet run end to end): `scripts/gcp/*`, the
   `gcsfuse` role task, and `scripts/aws/*` after the refactor out of live commands.
   Verify with a throwaway VM and delete it afterwards.
