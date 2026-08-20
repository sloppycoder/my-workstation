---
name: provision-ai-workstation
description: Interview the user, then provision an AWS EC2 dev workstation (optionally with a GNOME desktop + NICE DCV remote desktop, and a chosen subset of Claude Code CLI / Claude Desktop / Codex CLI / ChatGPT Desktop) by running AWS CLI and SSH commands directly, then handing off to the bundled Ansible role for the Linux-side bootstrap.
---

# Provision AI Workstation

Provisions a fresh AWS EC2 VM as a personal AI dev workstation. Unlike a typical
"run one script" provisioner, **the AWS-side orchestration is run as live,
individual commands by whoever is executing this skill** (Claude), not hidden
inside a wrapper script — so unexpected states (no default VPC, a changed
public IP, an already-existing security group, a failed AMI lookup) can be
seen and handled in the moment, the way this workstation was actually built
the first time. Only the deterministic, idempotent Linux-side bootstrap
(packages, user, desktop, DCV, apps) is scripted, via the Ansible role at
`runtime/ansible/`.

There is deliberately no stored provider-defaults file. Every run interviews
the user fresh — see below.

## 1. Interview (always ask, every run)

Ask these before touching AWS. Do not assume defaults from a previous run.

1. **Instance name** — free text, used as the `Name` tag and security group name.
2. **AWS region** — free text, no default (e.g. `ap-northeast-1`).
3. **Base image** — Debian 13 (trixie), official AWS AMI (preferred/default
   suggestion) vs. Ubuntu 24.04 LTS, official AWS AMI (alternative).
4. **GUI desktop login?** — yes/no. If yes, NICE DCV remote desktop is
   automatically included — do not ask about DCV separately.
5. **Components to install** — multi-select, none preselected by default:
   - Claude Code CLI
   - Codex CLI
   - Claude Desktop (requires GUI = yes)
   - ChatGPT Desktop (requires GUI = yes)

   If GUI = no and the user picks a desktop app, point out the conflict and
   ask them to either enable GUI or drop that app — don't silently drop it.
6. **Existing EC2 key pair name** — this skill only reuses an existing key
   pair, it never creates one. Ask which one, and confirm the matching
   private key path (default `~/.ssh/id_ed25519`).

Then **show a one-screen summary of the plan** (region, AMI, instance type,
GUI/DCV, components, key pair) and get explicit confirmation before running
`aws ec2 run-instances` — this spends real money and creates real
account-level resources (security group, possibly an IAM role).

Defaults if not overridden: instance type `m5.xlarge` / 40 GB gp3 root volume
when GUI = yes, `t3.large` / 20 GB when GUI = no. New Linux user: `aidev`,
passwordless sudo.

## 2. Procedure

Run each step as its own command via the Bash tool. `SKILL_DIR` below means
this skill's own directory (`.../skills/provision-ai-workstation`).

### 2.1 Resolve the AMI

Debian 13: owner `136693071363`, name filter `debian-13-amd64-*`, bootstrap
user `admin`. Ubuntu 24.04: owner `099720109477` (Canonical), name filter
`ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*`, bootstrap user
`ubuntu`.

```bash
aws ec2 describe-images --region "$REGION" --owners "$AMI_OWNER" \
  --filters "Name=name,Values=$AMI_NAME_FILTER" "Name=architecture,Values=x86_64" \
            "Name=state,Values=available" "Name=virtualization-type,Values=hvm" \
  --query 'reverse(sort_by(Images, &CreationDate))[0].[ImageId,RootDeviceName]' \
  --output text
```

Take `RootDeviceName` from the query result rather than hardcoding it — it
differs between Debian and Ubuntu AMIs.

### 2.2 Discover network

```bash
aws ec2 describe-vpcs --region "$REGION" --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text
```

Many accounts (including this one, in `ap-northeast-1`) have no default
VPC — don't treat that as an error. Fall back to listing all VPCs in the
region:

```bash
aws ec2 describe-vpcs --region "$REGION" \
  --query 'Vpcs[].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table
```

If exactly one VPC exists, use it and say so. If there are several, show the
table and ask the user which one. Then find a public subnet in it:

```bash
aws ec2 describe-subnets --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
  --query 'Subnets[].[SubnetId,AvailabilityZone]' --output table
```

If none have `MapPublicIpOnLaunch=true`, stop and ask the user how they want
to proceed instead of guessing — launching into a private subnet would leave
the instance unreachable given this skill doesn't set up a bastion/VPN.

### 2.3 Security group, locked to your current IP

```bash
MY_IP="$(curl -fsS https://checkip.amazonaws.com)"
aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=${INSTANCE_NAME}-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text
```

Create it if missing (`aws ec2 create-security-group ... --group-name
"${INSTANCE_NAME}-sg"`), then authorize ingress for the current IP:

- TCP 22, 80, 443 always (80/443 for testing local web servers/reverse
  proxies from your own browser — locked to your `/32` same as everything
  else here, not open to the world)
- TCP 8443 and UDP 8443 only if GUI = yes (DCV)

If the security group already existed from a previous run and its ingress
CIDR no longer matches `$MY_IP` (your IP changes over time/networks), revoke
the stale rule and re-authorize with the current IP rather than leaving two
rules stacked.

### 2.4 IAM instance profile (every instance, GUI or not)

Every instance gets the same instance profile attached — not gated on GUI
anymore, since most of what it grants is generally useful workstation
access, not just DCV licensing.

Reuse a single account-wide role/profile named `ai-workstation-role` across
all runs and all instances (check with `aws iam get-role` /
`get-instance-profile` before creating — don't recreate it per instance).
Trust policy: `ec2.amazonaws.com` may assume it. After creating a *new*
instance profile, wait ~10s before referencing it in `run-instances` — IAM
propagation lag will otherwise cause the launch to fail.

Inline policies:

- **`dcv-license-s3-read`** — `s3:GetObject` on `arn:aws:s3:::dcv-license.*/*`
  (wildcarded across regions). NICE DCV's free EC2 license check reads an
  object from an AWS-owned, per-region S3 bucket (`dcv-license.<region>`) via
  the instance's IMDS credentials — **without this, `dcvserver` will not come
  up** when GUI is enabled. Kept on every instance (harmless if GUI is off).
- **`workstation-access`**:
  - EC2, any region: `DescribeInstances`, `DescribeInstanceStatus`,
    `StartInstances`, `StopInstances`, `RebootInstances` — Resource `*` (EC2
    describe/start/stop/reboot don't support resource-level scoping)
  - S3, any bucket: `GetObject` + `PutObject` + `DeleteObject` +
    `AbortMultipartUpload` on `arn:aws:s3:::*/*`, `ListBucket` +
    `GetBucketLocation` on `arn:aws:s3:::*`, `ListAllMyBuckets` on `*`.
    `DeleteObject` and `AbortMultipartUpload` exist specifically so
    Mountpoint for S3 (`mount-s3`, installed by `install_mount_s3.yml`) can
    support deletes (`--allow-delete`) and writes (multipart uploads need to
    abort cleanly on failure) through the FUSE mount, not just via `aws s3`/
    `rclone`
  - Secrets Manager, any region: `GetSecretValue` on
    `arn:aws:secretsmanager:*:*:secret:*`, plus `ListSecrets` and
    `DescribeSecret` on `*` — `GetSecretValue` alone is only usable if the
    exact secret ARN is already known, so discovery permissions go with it
  - EBS: `CreateVolume`, `DeleteVolume`, `AttachVolume`, `DetachVolume`,
    `ModifyVolume`, `CreateSnapshot`, `DeleteSnapshot`, `CopySnapshot`,
    `CreateTags` — Resource `*`

Example policy document for `workstation-access`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Ec2StartStopStatus",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:RebootInstances"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3ReadWriteDeleteList",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload"
      ],
      "Resource": "arn:aws:s3:::*/*"
    },
    {
      "Sid": "S3BucketList",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::*"
    },
    {
      "Sid": "S3ListAllBuckets",
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    },
    {
      "Sid": "SecretsManagerReadAndDiscover",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:ListSecrets",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EbsVolumeAndSnapshotManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:ModifyVolume",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot",
        "ec2:CopySnapshot",
        "ec2:CreateTags"
      ],
      "Resource": "*"
    }
  ]
}
```

**Deliberately not granted**: `ec2:TerminateInstances`, `ec2:RunInstances`
(launching new instances), and anything touching security groups, VPCs, or
IAM itself. (`s3:DeleteObject` *was* on this list in an earlier version of
this policy — it was added deliberately once Mountpoint for S3 needed it for
`--allow-delete` support; don't re-remove it without checking whether that's
still needed.)
Treat any expansion of this list as a decision for the user to make
explicitly, not something to infer from a task.

### 2.5 Launch

```bash
aws ec2 run-instances --region "$REGION" \
  --image-id "$IMAGE_ID" --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" \
  --iam-instance-profile Name=ai-workstation-role \
  --block-device-mappings "[{\"DeviceName\":\"$ROOT_DEVICE_NAME\",\"Ebs\":{\"VolumeSize\":$ROOT_VOLUME_GB,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
  --network-interfaces "[{\"DeviceIndex\":0,\"SubnetId\":\"$SUBNET_ID\",\"Groups\":[\"$SECURITY_GROUP_ID\"],\"AssociatePublicIpAddress\":true}]" \
  --tag-specifications "[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"$INSTANCE_NAME\"},{\"Key\":\"ManagedBy\",\"Value\":\"provision-ai-workstation\"}]}]" \
  --query 'Instances[0].InstanceId' --output text
```

Then:

```bash
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-status-ok --region "$REGION" --instance-ids "$INSTANCE_ID"
aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
```

Poll SSH (`ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i
"$PRIVATE_KEY" "$REMOTE_USER@$PUBLIC_IP" echo ready`) every ~5s until it
succeeds, up to a few minutes.

### 2.6 Linux-side bootstrap (Ansible)

This part **is** a script, deliberately — it's proven and doesn't benefit
from live improvisation.

```bash
cd "$SKILL_DIR/runtime/ansible"
./setup "$PUBLIC_IP" "$REMOTE_USER" \
  --private-key "$PRIVATE_KEY" \
  -e "new_user_name=aidev" -e "new_user_sudoer=true" \
  -e "enable_gui=$GUI_BOOL" \
  -e "install_claude_code=$INSTALL_CLAUDE_CODE_BOOL" \
  -e "install_claude_desktop=$INSTALL_CLAUDE_DESKTOP_BOOL" \
  -e "install_chatgpt_desktop=$INSTALL_CHATGPT_DESKTOP_BOOL"
```

The role (`runtime/ansible/roles/common/tasks/`): base packages (includes
`ddclient`) → create `aidev` user (+ `sudo` group membership when GUI is
enabled, needed for GNOME/polkit prompts — sudoers.d alone isn't recognized
by polkit) → `uv` → oh-my-zsh → GitHub CLI → rclone (`install_rclone.yml`,
always runs, not part of the interview — see below) → Mountpoint for S3
(`install_mount_s3.yml`, always runs — see below) → `ddclient.conf`
(`install_ddclient.yml`, always runs, dummy Cloudflare values — see below) →
GNOME desktop + Xdummy virtual framebuffer + Chrome (`install_gui_desktop.yml`,
when GUI) → NICE DCV (`install_dcv.yml`, when GUI) → Claude Code CLI / Claude
Desktop / ChatGPT Desktop, each independently gated on the interview answer.

**rclone**: every instance gets `rclone` installed unconditionally — not part
of the interview, don't ask about it. Debian and Ubuntu's own apt packages
are stuck on 1.60.1, so it's installed via the official `rclone.org/install.sh`
installer instead to get a current version. No backend is configured with
credentials; that's left for the user to do interactively with `rclone
config`.

**Mountpoint for S3 (`mount-s3`)**: every instance gets `mount-s3` installed
unconditionally too, from the official `.deb` at
`s3.amazonaws.com/mountpoint-s3-release`, with its GPG signature verified
against AWS's published key before install (fail the play on a bad
signature, don't silently continue). Unlike `rclone`, it needs no separate
config step — it picks up credentials automatically from the instance's IAM
role (`ai-workstation-role`, §2.4), which already grants
`GetObject`/`PutObject`/`DeleteObject`/`AbortMultipartUpload`/`ListBucket` on
every bucket. Usage: `mount-s3 <bucket> <mountpoint>` (add `--allow-delete`
to enable `rm` on the mount).

**ddclient**: every instance gets `ddclient` installed and `/etc/ddclient.conf`
written with placeholder values (`zone=example.com`,
`hostname=workstation.example.com`, `password=REPLACE_WITH_REAL_CLOUDFLARE_API_TOKEN`)
— this exists because the instance has no Elastic IP, so its public IP
changes on every stop/start. The service starts and polls
`checkip.amazonaws.com` every 5 minutes, but Cloudflare auth will fail until
someone edits the real zone/hostname/token in and runs `sudo systemctl
restart ddclient`. Mention this placeholder-only state in the final report so
it isn't mistaken for a working dynamic DNS setup. Real values can also be
passed at provision time via `-e ddclient_zone=... -e ddclient_hostname=...
-e ddclient_cloudflare_api_token=...` if the user gives them during the
interview — don't ask for them by default, only use if offered.

### 2.7 Codex CLI — install separately, not through Ansible

Codex's own installer (`curl -fsSL https://chatgpt.com/codex/install.sh |
sh`) **hangs indefinitely under Ansible's `become`**: `become` allocates a
pty, and the installer's trailing interactive shell never receives EOF on it.
If Codex CLI was selected, install it with a direct SSH command instead,
after the Ansible run completes (the `aidev` user's `authorized_keys` already
trusts the same private key):

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$PRIVATE_KEY" \
  "aidev@$PUBLIC_IP" 'curl -fsSL https://chatgpt.com/codex/install.sh | sh' < /dev/null
```

The explicit `< /dev/null` matters even outside Ansible — leave it in.

### 2.8 If GUI was enabled: reboot once and verify

```bash
ssh ... "aidev@$PUBLIC_IP" 'sudo reboot'
# wait for SSH to come back, then:
ssh ... "aidev@$PUBLIC_IP" \
  'for s in gdm dcvserver dcv-console-session; do printf "%s: " "$s"; systemctl is-active "$s"; done'
```

All three should report `active`. This confirms the desktop, DCV, and the
console-session unit all survive a cold boot unattended, not just the
in-progress session from installation.

**SSH coming back does not mean this check is safe to run yet.** Observed
live: SSH accepted connections while `dcv-console-session` was still
`inactive`, and only flipped to `active (exited)` about 30-40s later once
`dcvserver` itself finished starting (the unit's `Requires=dcvserver.service`
means it waits on that). A single immediate check after SSH returns will
report a false failure. Either retry the `systemctl is-active` loop a few
times over ~60s before concluding something is actually broken, or sleep an
extra 30-45s after SSH comes back before checking once — don't report a
false "dcv-console-session is broken" from a single early check.

### 2.9 Report back to the user

- SSH commands for both the bootstrap user and `aidev`
- If GUI: DCV URL (`https://<public-ip>:8443`, self-signed cert — click
  through the browser warning), username `aidev`, and that the password is in
  `/root/aidev_dcv_password.txt` on the instance (`sudo cat` it, or rotate
  with `sudo passwd aidev`)
- Which components were installed, and remind the user that Claude Code CLI,
  Claude Desktop, ChatGPT Desktop, and Codex CLI all require an **interactive
  sign-in on first use** — none of this can be pre-authenticated headlessly
- Note: no Elastic IP is attached, so the public IP changes on every
  stop/start — mention this, don't silently work around it
- `ddclient` is installed and running but `/etc/ddclient.conf` still has
  placeholder Cloudflare values — dynamic DNS is not actually working until
  someone fills in the real zone/hostname/token

## 3. Known gotchas (already fixed in the role, keep them fixed)

1. NICE DCV has no official Debian build. The Ubuntu 24.04 x86_64 build
   installs and runs on Debian 13 anyway (glibc/systemd close enough), but
   this is unsupported by AWS/NICE, not just untested — flag it as a caveat
   when Debian + GUI is chosen.
2. DCV's license check needs the IAM instance profile from §2.4 attached
   *before* `dcvserver` starts, or it fails Access Denied.
3. `automatic-console-session` in `/etc/dcv/dcv.conf` does not reliably
   create a session at boot — the role uses a systemd oneshot unit instead
   (`dcv-console-session.service`).
4. `gnome-core` + `gdm3` can leave `display-manager.service` stale on this
   AMI — the role reasserts the symlink after install.
5. `pulseaudio-utils` is required for DCV microphone redirection but isn't
   pulled in by any GNOME package — it's in the role's package list.
6. GNOME/polkit GUI privilege prompts only recognize actual `sudo` group
   membership, not `sudoers.d` `NOPASSWD` entries — the role adds `aidev` to
   `sudo` when GUI is enabled. Takes a fresh login to apply.
7. Codex CLI's installer is incompatible with Ansible `become` — always
   install it via a direct SSH command (§2.7), never as an Ansible task.
8. After the post-GUI reboot, SSH comes back before `dcv-console-session`
   settles (it waits on `dcvserver` via `Requires=`) — observed ~30-40s of
   lag where the unit reads `inactive` before flipping to `active (exited)`.
   Retry the service check over ~60s (§2.8), don't trust a single
   immediate read.
