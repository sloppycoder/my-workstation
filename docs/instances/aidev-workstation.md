# aidev Tokyo AI Workstation

EC2 remote workstation for AI agent work, provisioned in `ap-northeast-1`
(Tokyo) — before `provision-vm` existed as a skill, this
instance is what the skill was extracted from.

See [../../CLAUDE.md](../../CLAUDE.md) for the skill this instance came from
and the account-wide provisioning notes.

## Instance

| | |
|---|---|
| Instance ID | `i-0c604ef60d36ad80e` |
| Name tag | `aidev-workstation` |
| Region / AZ | ap-northeast-1 (Tokyo) / ap-northeast-1c |
| Type | m5.xlarge (4 vCPU / 16 GB RAM) |
| AMI | `ami-0e427b12d3ebd06d9` — official Debian 13 (trixie), `debian-13-amd64-20260810-2566` |
| Root disk | 40 GB gp3 |
| Public IP | `13.112.7.103` (**changes on every stop/start** — no Elastic IP attached. Check `aws ec2 describe-instances` for the current address before connecting.) |
| Key pair | `m1air` (`~/.ssh/id_ed25519` on this Mac) |
| Security group | `aidev-workstation-sg` (`sg-06d509330b0b837d8`) — ports 22 and 8443 (tcp+udp) open only to the provisioning machine's public IP at the time (`50.224.68.74/32`). If that IP changes, add a new ingress rule before connecting again. |
| IAM instance profile | `aidev-workstation-role` (renamed from `aidev-workstation-dcv-license` once its scope grew beyond just licensing — old role/profile deleted, swapped live via `replace-iam-instance-profile-association`, no downtime) — see **IAM role permissions** below |

## Access

```
ssh admin@13.112.7.103   # original Debian AMI user
ssh aidev@13.112.7.103   # provisioned dev user, passwordless sudo
```

Both use the `m1air` key already in `~/.ssh/id_ed25519` on this Mac.

## IAM role permissions

`aidev-workstation-role`, attached as the instance profile — account-wide, all regions
(no region condition on the policies):

- **`dcv-license-s3-read`** — `s3:GetObject` on `arn:aws:s3:::dcv-license.ap-northeast-1/*`
  only. Required for NICE DCV's free EC2 license check.
- **`s3-and-ec2-broad-access`**:
  - S3: `GetObject` + `PutObject` on every bucket's objects (`arn:aws:s3:::*/*`), plus
    `ListBucket` + `ListAllMyBuckets`
  - EC2: `Describe*` (all read-only queries) + `StartInstances` + `StopInstances` +
    `RebootInstances`
  - EBS: create/delete/attach/detach/modify volumes; create/delete/copy snapshots;
    `CreateTags`

**Deliberately not granted:** `s3:DeleteObject` (only read/write was requested, not
delete), `ec2:TerminateInstances`, `ec2:RunInstances` (launching new instances), and
anything touching security groups, VPCs, or IAM itself. Ask if any of these are needed.

## `aidev` user setup

Provisioned via the Ansible playbook that later became
[../../skills/provision-vm/runtime/ansible](../../skills/provision-vm/runtime/ansible)
(originally run out of `linux-vm-provisioner`'s equivalent role with
`enable_local_model_serving=false`, `new_user_sudoer=true`):

- Shell: zsh, with oh-my-zsh + `zsh-autosuggestions` + `zsh-peco-history`
- `.gitconfig` seeded from the playbook template
- Passwordless sudo via `/etc/sudoers.d/aidev` (CLI `sudo` works immediately). Also added
  to the `sudo` Unix group afterward so GNOME/polkit GUI prompts (Settings → timezone,
  etc.) authenticate as `aidev` instead of falling back to `admin` — the original
  cloud-init user, display name "Debian" from its GECOS field, whose password is locked
  (SSH-key-only), which made those GUI prompts a dead end before this fix. **Group
  membership changes need a fresh login to take effect** — if GUI prompts still show
  "Debian" after this, log `aidev` out and back in (or restart the DCV console session).
- `uv` (Astral) and GitHub CLI (`gh`) installed
- Claude Code CLI installed (`~/.local/bin/claude`, wrapper script `cc`)
- Base packages: git, htop, jq, peco, tmux, unzip, wget, zip, acl, telnet

OpenAI Codex CLI 0.148.0 — installed natively for `aidev` via the official installer
(`curl -fsSL https://chatgpt.com/codex/install.sh | sh`), at `~/.local/bin/codex`
(already on `aidev`'s `$PATH` via `.zshrc`). Briefly installed via `npm install -g
@openai/codex` first, then uninstalled in favor of the native binary — `nodejs` v20.19.2
/ `npm` 9.2.0 remain installed from the Debian apt repo regardless. The same installer
had hung during initial provisioning under Ansible's `become` (which allocates a pty,
so the installer's trailing interactive shell never received EOF and blocked forever);
running it directly as `sudo -iu aidev ... < /dev/null` avoided that and completed
cleanly — this is why `provision-vm` installs Codex via a direct SSH step
instead of an Ansible task. Not yet authenticated — run `codex` and sign in with
ChatGPT on first use.

## Extra packages

- `redis-server` (running, `redis-cli ping` → `PONG`)
- `pulseaudio-utils` — required for DCV microphone redirection (AWS's own docs list it as
  a prerequisite; it wasn't in the original desktop provisioning script). With it
  installed, DCV exposes a virtual mic (`AWS-Virtual-Microphone`, PipeWire-backed) as the
  session's default audio input, set automatically when the client enables its mic.
  Verified end-to-end with a live `parecord` test. If mic audio doesn't come through in
  the desktop, first check the **microphone toggle inside DCV Viewer itself** and macOS's
  mic permission grant for DCV Viewer (System Settings → Privacy & Security → Microphone)
  before assuming a server-side issue.
- Google Chrome (`google-chrome-stable`, official Google apt repo)
- Claude Desktop (`claude-desktop`, official Anthropic apt repo — launch from the GNOME
  app menu or `claude-desktop` and sign in interactively; updates arrive via
  `apt update && apt upgrade`)
- ChatGPT Desktop (`chatgpt`, official OpenAI Linux preview app, installed from
  `persistent.oaistatic.com` — registers its own apt repo at
  `/etc/apt/sources.list.d/chatgpt.sources` for future updates; launch via `chatgpt` or
  the GNOME app menu and sign in interactively. This is an OpenAI public preview, so
  expect rough edges.)
- `rclone` v1.75.0 — installed via the official `rclone.org/install.sh` script (Debian's
  own apt package is a stale 1.60.1, still true as of Ubuntu 24.04 / Debian 13 — this is
  why `provision-vm` always installs rclone this way). Google Drive support
  is built into rclone itself, no separate plugin needed — run `rclone config` and pick
  the `drive` backend.
- `mount-s3` v1.23.0 (AWS Mountpoint for Amazon S3) — official `.deb` from
  `s3.amazonaws.com/mountpoint-s3-release`, GPG signature verified against AWS's published
  key before install. FUSE-mount an S3 bucket with e.g. `mount-s3 <bucket> <mountpoint>`.
  (Not included in the `provision-vm` skill — installed manually on this
  instance only.)

`rclone` has not been configured with credentials on this instance — package only, per
request. `mount-s3` **is** configured (see below).

## `gphoto` S3 mount (mount-s3)

Successor to a standalone `gphoto` EC2 instance (`i-041fc8fa02020f777`, us-west-2,
decommissioned 2026-08-19 — see **Notes / caveats**) that used to hold Google Photos
takeout data and a `track_me.db` app database, mounted the same way. That instance and
its original bucket (`gphoto-025604691335`) were deleted; this workstation now serves the
equivalent role with a fresh, empty bucket in Tokyo:

- Bucket: `gphoto-hahayshi3`, regional in `ap-northeast-1` (created fresh — not migrated
  from the old bucket's contents, which were deemed disposable and deleted)
- Mounted at `/mnt/gphoto` via `mount-s3`, managed by systemd unit
  `mount-gphoto.service` (enabled at boot):
  ```
  ExecStart=/usr/bin/mount-s3 gphoto-hahayshi3 /mnt/gphoto --region ap-northeast-1 \
    --allow-other --uid 1001 --gid 1001 --allow-overwrite
  ```
- uid/gid `1001` matches `aidev`, mirroring the old instance's convention
- No `--allow-delete` — `aidev-workstation-role` deliberately lacks `s3:DeleteObject`
  (see **IAM role permissions** above), unlike the old `gphoto-vm-s3-profile` role. Ask if
  delete access should be added to match the old setup.
- Auth via the instance's own IAM role, same pattern as the rest of this instance's
  `mount-s3` usage.

- Google Cloud CLI (`google-cloud-cli` 581.0.0 — `gcloud`, `gsutil`, `bq`, alpha/beta
  components) — official Google apt repo (`packages.cloud.google.com/apt`), system-wide,
  available to both `admin` and `aidev`. Not yet authenticated — run `gcloud init` or
  `gcloud auth login`. (Also not included in the skill — manual on this instance only.)

## Desktop / remote access (NICE DCV)

- Desktop: GNOME (`gnome-core` + `gdm3`), Xorg session (Wayland disabled — required by DCV)
- No GPU on this instance, so the Xdummy driver provides a virtual framebuffer and OpenGL
  runs in Mesa software rendering — usable but not GPU-accelerated
- NICE DCV server installed using the **Ubuntu 24.04 x86_64 build** — Debian isn't an
  officially supported DCV target, but trixie's glibc/systemd are close enough that it
  installs and runs cleanly
- A console session for `aidev` is created automatically at boot via a systemd unit
  (`/etc/systemd/system/dcv-console-session.service`, `WantedBy=graphical.target`) —
  the built-in `automatic-console-session` setting in `/etc/dcv/dcv.conf` did not
  reliably trigger session creation, so this unit is the mechanism actually in effect
- Verified: instance was rebooted and `gdm`, `dcvserver`, the console session, and
  `redis-server` all came back up automatically with no manual intervention

**Connect:**

- Browser: `https://13.112.7.103:8443` (self-signed cert — click through the browser warning)
- Or the NICE DCV Viewer desktop app, same address
- Username: `aidev`
- Password: see `/root/aidev_dcv_password.txt` on the instance, or rotate it any time with
  `sudo passwd aidev`

> The DCV login password is **not** included in this file on purpose — read it from the
> instance directly, and don't commit it anywhere.

## Dynamic DNS (ddclient → Cloudflare)

Since the instance has no Elastic IP and its public address changes on every
stop/start, `ddclient` (Debian's `ddclient` 3.11.2-2 package, native
`cloudflare` protocol support) keeps `station.vino9.net` pointed at the
current address:

- Config: `/etc/ddclient.conf` (root-only, mode `600`)
- Checks the public IP via `https://checkip.amazonaws.com` every 5 minutes
  (`daemon=5m`), then updates the Cloudflare `A` record for
  `station.vino9.net` in the `vino9.net` zone via the Cloudflare API token
  auth method (`login=token`)
- Service: `ddclient.service` (systemd), enabled at boot, currently running
  with a **dummy placeholder API token** — `password=` in the config is
  `REPLACE_WITH_REAL_CLOUDFLARE_API_TOKEN` and needs to be swapped for a real
  Cloudflare API token scoped to the `vino9.net` zone with **Zone - DNS -
  Edit** and **Zone - Zone - Read** permissions. After updating it, run
  `sudo systemctl restart ddclient`.
- The `station.vino9.net` DNS record itself was created directly in the
  Cloudflare dashboard (not via CLI — no working Cloudflare CLI was found on
  the provisioning Mac; the only trace was a leftover `cloudflared`
  LaunchDaemon pointing at a since-removed binary, and `cloudflared` is a
  tunnel client, not a DNS-record management tool anyway).
- Verified end-to-end except for the final Cloudflare write: `ddclient -force
  -verbose` correctly detects the current public IP and correctly calls
  `api.cloudflare.com`, failing only on the dummy token's invalid
  `Authorization` header format (Cloudflare error 6003/6111) — confirms
  network path and request construction are both correct.

This exact pattern (dummy Cloudflare config, real values filled in later) is
now baked into `provision-vm` for every instance it creates —
see `install_ddclient.yml` in the skill's Ansible role.

## Notes / caveats

- Debian is unsupported-but-working for NICE DCV; if a future DCV release drops
  compatibility with the Ubuntu 24.04 package's dependencies, reinstalling against a
  newer Ubuntu build tag may be needed.
- The security group is locked to a single `/32` CIDR. Widen it (or switch to a VPN /
  Session Manager tunnel) if you need to connect from a different network.
- No instance-store/EBS snapshot or backup schedule was configured — the 40 GB root
  volume is the only copy of this workstation's state.
- `apt update && apt upgrade` has been run and completed cleanly (no held/broken packages,
  no reboot required). All services (`gdm`, `dcvserver`, `dcv-console-session`,
  `redis-server`) were confirmed active afterward.
- **Retired `gphoto` instance (2026-08-19):** a separate, undocumented EC2 instance
  (`i-041fc8fa02020f777`, `t3.medium`, us-west-2) discovered live in a prior session —
  never part of `provision-vm`. It mounted an S3 bucket
  (`gphoto-025604691335`) holding Google Photos takeout data and a `track_me.db` app
  database via the same `mount-s3` pattern used here. Before deletion, its 20 GB root
  EBS volume was snapshotted to `snap-0ade800e479d7635e` (us-west-2, **not copied
  anywhere else — the only backup**); the instance was then terminated and the S3 bucket
  emptied and deleted, since the bucket's contents were confirmed disposable. Its IAM
  instance profile (`gphoto-vm-s3-profile`) and security group (`sg-05885c47edbc691ff`)
  were left in place, not cleaned up. The `gphoto` mount role now lives on this
  workstation instead — see **`gphoto` S3 mount (mount-s3)** above.
