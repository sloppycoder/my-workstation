---
name: vm-lifecycle
description: |
  Manage the life cycle of a VM made with provision-vm: take/refresh its "seed"
  snapshot (the root disk, used to boot the VM again), recreate the VM from the
  seed, add/remove a throwaway scratch disk, shelve (snapshot + delete the VM),
  or destroy everything. Works on AWS and GCP. Creates and deletes billed cloud
  resources, so it is user-invoked only.
  Usage: "vm-lifecycle <name> [seed|create|add scratch [GB]|delete scratch|shelve|destroy]"
disable-model-invocation: true
---

# vm-lifecycle

Scripts are in `scripts/gcp/` and `scripts/aws/` (same names, same flags). Pick the
folder from `PROVIDER` in `~/.config/station-vm/<name>.env`, which
`provision-vm/scripts/register.sh` writes. Every script is `script.sh NAME [args]`,
prints what it does, and the destructive ones **only print a plan unless run with
`--yes`**: run without `--yes`, show the plan, get an explicit go-ahead, then re-run.
Run them from the user's laptop, never on the VM being changed.

## The idea

The VM is disposable; only the **seed snapshot** of its root disk persists. Configure
a VM once (rclone, sign-ins, git clones), snapshot it as the seed, then delete or
recreate the VM at will. Per VM there is exactly one seed (a refresh replaces it,
the old one is deleted only after the new one is READY). The **scratch disk**
(`/mnt/scratch`) is separate, is never snapshotted, and costs money only while it
exists. A stopped VM still bills for its disks.

| Step | Script | Notes |
|---|---|---|
| First seed / refresh seed | `shelve_vm.sh NAME [--yes]` | Stops the VM for a consistent snapshot, snapshots the root disk, restarts it. The scratch disk is not included. |
| Shelve | `shelve_vm.sh NAME --delete [--yes]` | Same, then deletes the VM and **all** its disks (scratch data is lost). |
| Recreate | `create_vm.sh NAME [--machine-type T]` | New VM (root disk) from the seed; refreshes the firewall/SG source IP and the `ssh NAME` alias. |
| Add scratch | `add_scratch.sh NAME [GB]` | Default 150 GB. Attaches live; starts the VM only if it is stopped. Formats if blank, mounts `/mnt/scratch` (mode 1777). One per VM. |
| Remove scratch | `del_scratch.sh NAME [--stop] [--yes]` | Unmounts and detaches live; if the disk is busy (or with `--stop`) stops the VM first. **No backup; all data lost.** |
| Destroy | `destroy_vm.sh NAME [--yes]` | Deletes the VM, every disk, every seed, and the local config. Irreversible. |

## Rules for running them

- **Seed / refresh**: tell the user the VM will be stopped for a few minutes and
  restarted (its public IP changes). If it's the first seed, say so.
- **Scratch**: ask how big if not given (default **150 GB**). Before `del_scratch.sh
  --yes`, state that everything on the disk is lost and cannot be recovered, and that
  anything using `/mnt/scratch` will be interrupted.
- **Shelve --delete / destroy**: show the plan, name the VM and what is deleted
  (for destroy: *including the seed snapshot, so the VM cannot be recreated*), and get
  an explicit yes naming the VM. Never pass `--yes` on your own initiative.
- Only one seed snapshot exists per VM; `shelve_vm.sh` names it
  `<name>-seed-<UTC timestamp>` (GCP: label `station-vm-seed`; AWS: AMI tag of the
  same name) and removes older ones afterwards.
- The public IP is ephemeral; scripts that start/create a VM refresh the ssh alias,
  drop stale `known_hosts` entries and wait for ssh.
- Provider quirks are handled in the scripts: gcloud's long wait call may be dropped
  by a proxy (they tolerate the error and poll the real state), and the AWS seed is an
  AMI created with the scratch device excluded.

## Machine type unavailable (`create_vm.sh` exit 5)

If the type stored in the config (`MACHINE_TYPE`/`INSTANCE_TYPE`) is unavailable in
the zone or out of capacity, `create_vm.sh` prints `MACHINE_TYPE_UNAVAILABLE=<type>`
and exits **5**, having cleaned up (the half-made boot disk is deleted). Don't
retry the same type. Run `provision-vm/scripts/<provider>/similar_types.sh` (same
vCPU, memory ±25%), ask the user to pick (offer the closest 2–3, with a
recommendation), and re-run with `--machine-type` / `--instance-type`. If they say
"any similar one", choose the closest yourself (same family first, then cheapest) and
say what you chose. Offer to update the type in `~/.config/station-vm/<name>.env`
if the new one should be the default.

## Settings

Per-VM settings: `~/.config/station-vm/<name>.env` (see above). Optional user-wide
`~/.config/station-vm/defaults.env` is loaded first; the per-VM file overrides it.
Useful keys: `SEED_PREFIX` (seed snapshot/AMI name prefix, default the VM name),
`SNAPSHOT_LOCATION` (GCP storage location, e.g. `us`), `MACHINE_TYPE`.

## Status

Untested end to end on a live VM except the read-only plan output (`--yes` omitted).
The GCP scripts are ported from a tracker skill that was tested on 2026-11-01; the
parts that are new here (single seed with label, live scratch detach, config file,
AWS scripts) have not been run for real. Test on a throwaway VM first.
