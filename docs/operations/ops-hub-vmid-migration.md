# Runbook — Migrating ops-hub-A from VMID 104 to 600 (+ allocator fencing)

**Audience:** operator, with an agent driving. **Runtime:** ~10 min, of which the control plane is
down for ~2–3. **Prereq:** root on `dna` (`ssh -i ~/.ssh/powernode-deploy admin@dna`, passwordless
sudo). **Risk:** moderate — it stops the self-hosted control plane. Every step is reversible and the
rollback is the same commands with the arguments swapped.

> **This runbook is executed entirely from `dna` via `qm`/`zfs`/`mv`, never through the platform
> API.** ops-hub *is* the platform: the moment it stops, the API, the MCP server, and the Rails
> console all go with it. Anything that needs the platform (step 6) happens only after it is back up.

## Why

VMID 104 sits in the hand-made band — 100–114, 200–220, 300–301 (`ops-old`, `vault`, `cucm-pub`,
`gns`, `dev`…). Its immediate neighbour is **VM 105, `opn-1`, the production firewall.** A mistyped
`qm stop 105` is one keystroke from taking the site's network down, and the control plane is the VM
an operator touches most often under pressure. Moving it out of that neighbourhood is worth a short
outage on its own; doing it before P1-a means ops-hub-B can be numbered coherently from the start
(**600 = A, 601 = B**) instead of needing a second migration later.

## The allocator fencing is a PREREQUISITE, not a follow-up

Do §1 before §2. Until the bands are closed, nothing stops another plane's allocator from taking
600 or 601 while the migration is in flight.

`ProxmoxProvider#allocate_next_vmid!` supported `vmid_min` — a floor — and no ceiling. **A floor is
not a reservation.** The search walks upward without limit, skipping ids already in use, so a band
"reserved" by convention above a floored connection is reached as soon as that connection's own
range fills. Live today: the dev plane's `ipnode-pve-conn` has `vmid_min: 500, vmid_max: nil`, and
the ops-hub plane floors at 9000 (which is why its builders are sitting at 9003/9004). With 500–599
full, dev's next allocation is **600** — ops-hub-A's new id. `vmid_max` now closes the band and
**raises on exhaustion instead of spilling upward**, because spilling is exactly the cross-plane
collision the floor exists to prevent, so failing to provision is the better outcome and the one an
operator can actually see.

### §1 — Apply the fencing (both planes; nothing is stopped for this)

Bands: dev **500–599**, ops-hub **9000–9099**, control plane **600–609** (fenced out of both, 8 spare
for future members).

On **each** plane's Rails console, for the connection pointing at `https://dna.ipnode.net:8006`:

```ruby
# dev plane — connection "ipnode-pve-conn"
c = System::ProviderConnection.find_by(name: "ipnode-pve-conn")
c.update!(config: c.config.merge("vmid_min" => 500, "vmid_max" => 599))

# ops-hub plane — same cluster, its own connection row (floor is 9000)
c = System::ProviderConnection.find_by(endpoint_url: "https://dna.ipnode.net:8006")
c.update!(config: c.config.merge("vmid_min" => 9000, "vmid_max" => 9099))
```

Verify on each: `System::ProviderConnection.find(...).config.values_at("vmid_min","vmid_max")`.

> **Do not skip the ops-hub plane** because its floor already sits above 600. Its band needs a
> ceiling for the same reason dev's does — the next reserved block someone adds above 9099 would
> have the identical problem, and a half-fenced fleet invites exactly the assumption that bit here.

## §2 — Pre-flight (all read-only; abort on any surprise)

```bash
ssh -i ~/.ssh/powernode-deploy admin@dna
sudo qm status 104                      # expect: running
sudo qm config 104 | grep -E 'protection|parent|cicustom|net0|smbios1'
sudo qm listsnapshot 104                # expect: pre-agent-module-v28, then "current"
sudo zfs list -r local-zfs/local-data | grep 104
sudo qm status 600 2>&1                 # expect: "does not exist"
sudo zfs list -H -o name -r local-zfs/local-data | grep -E 'vm-60[01]-'   # expect: nothing
```

Record `qm config 104` in full before touching anything. It is the rollback reference.

**What must be preserved, and is, because the config file moves intact:**

| Item | Value today | Why it matters |
|---|---|---|
| `net0` MAC | `12:25:78:03:0B:56` | The DHCP lease behind **10.125.0.227**. The whole fleet reaches ops-hub there. Change this and every enrolled node loses its control plane. |
| `smbios1` uuid | `4dfd44e4-…` | Guest-visible machine identity. |
| `onboot: 1` | set | The only thing that restarts ops-hub after a host reboot, now that Proxmox HA is deliberately not used. |
| `parent` / snapshot | `pre-agent-module-v28` | The rollback point for the agent module work. ZFS snapshots travel with `zfs rename`. |

## §3 — Disarm the auto-restart FIRST

**This step is not optional and it is not obvious.** `powernode-ops-hub-qmstart-retry` is **armed**
on dna and hardcodes `VMID="${VMID:-104}"`. It is level-triggered and fires every 30s. The moment
step 4 stops VM 104, the retry sees "VM stopped, storage active" and issues `qm start 104` — mid
rename, against a config that is being moved out from under it. Disarm it before stopping anything.

```bash
sudo systemctl stop powernode-ops-hub-qmstart-retry.timer
sudo mv /etc/powernode/qmstart-retry.armed /etc/powernode/qmstart-retry.armed.migrating
sudo systemctl is-active powernode-ops-hub-qmstart-retry.timer   # expect: inactive
```

## §4 — Stop, rename, restart

```bash
# 4a. clear the protection flag (it is re-set in 4g; leaving it off is the one
#     state you must not walk away from)
sudo qm set 104 --protection 0

# 4b. graceful stop, then CONFIRM stopped — do not proceed on a timeout
sudo qm shutdown 104 --timeout 120
sudo qm status 104                      # must read: stopped

# 4c. rename the three zvols. Metadata-only on ZFS: instant, no data copied.
#     Snapshots move with the dataset.
sudo zfs rename local-zfs/local-data/vm-104-disk-0    local-zfs/local-data/vm-600-disk-0
sudo zfs rename local-zfs/local-data/vm-104-disk-1    local-zfs/local-data/vm-600-disk-1
sudo zfs rename local-zfs/local-data/vm-104-cloudinit local-zfs/local-data/vm-600-cloudinit
sudo zfs list -r local-zfs/local-data | grep -E 'vm-(104|600)-'   # expect: only vm-600-*

# 4d. cloud-init snippets are named by VMID on dsm-data. Rename them, because
#     104 becomes free after this and a future VM 104 would otherwise generate
#     its own 104-user.yml and clobber the file this VM's config points at.
sudo mv /mnt/pve/dsm-data/snippets/104-user.yml /mnt/pve/dsm-data/snippets/600-user.yml
sudo mv /mnt/pve/dsm-data/snippets/104-meta.yml /mnt/pve/dsm-data/snippets/600-meta.yml

# 4e. move the config + per-VM firewall, then repoint every id reference.
#     The sed covers the snapshot sections too — they carry their own disk lines.
sudo mv /etc/pve/nodes/dna/qemu-server/104.conf /etc/pve/nodes/dna/qemu-server/600.conf
sudo mv /etc/pve/firewall/104.fw /etc/pve/firewall/600.fw
sudo sed -i -e 's/vm-104-/vm-600-/g' -e 's#snippets/104-#snippets/600-#g' \
            /etc/pve/nodes/dna/qemu-server/600.conf

# 4f. VERIFY BEFORE STARTING. No 104 references may remain, and the MAC must be
#     unchanged. A cicustom pointing at a missing snippet fails the start.
sudo grep -nE '104' /etc/pve/nodes/dna/qemu-server/600.conf    # expect: no output
sudo qm config 600 | grep -E 'net0|efidisk0|scsi0|ide2|cicustom|onboot'
sudo ls -l /mnt/pve/dsm-data/snippets/600-*.yml

# 4g. start and re-protect
sudo qm start 600
sudo qm set 600 --protection 1
```

## §5 — Verify the guest actually came back

```bash
sudo qm status 600                                   # running
curl -sk -o /dev/null -w '%{http_code}\n' https://10.125.0.227/up      # 200
ping -c2 10.125.0.227                                # same IP — proves the MAC/lease survived
sudo qm listsnapshot 600                             # pre-agent-module-v28 still present
```

Do not continue until `/up` returns 200. If it does not, go to **Rollback**.

## §6 — Re-point everything that still says 104

The VM is running; these are the facets that make it *managed* again. Skipping any one leaves a
silent gap — the platform managing a VM it thinks is elsewhere, or an auto-restart guarding a VM
that no longer exists.

**6a. The auto-restart guard** (on dna) — repoint, then re-arm:

```bash
sudo systemctl edit powernode-ops-hub-qmstart-retry.service   # set Environment=VMID=600
sudo mv /etc/powernode/qmstart-retry.armed.migrating /etc/powernode/qmstart-retry.armed
sudo systemctl start powernode-ops-hub-qmstart-retry.timer
sudo journalctl -u powernode-ops-hub-qmstart-retry -n5        # expect: "already running" for 600
```

Also update the repo default so a fresh deploy does not reintroduce 104:
`scripts/monitoring/ops-hub-qmstart-retry.sh` → `VMID="${VMID:-600}"`.

**6b. The platform's own record** (on the ops-hub plane, once it is up).

> **`cloud_instance_id` is a key inside the `config` jsonb, NOT a column.** Querying it as a column
> raises `PG::UndefinedColumn`. The name appears as a top-level field in provider serializer output,
> which is where the wrong assumption comes from.

> **Do NOT blanket-update everything matching `/104`.** VMIDs get reused over time, so old rows
> legitimately reference 104 and are not ops-hub. On the dev plane this matched **seven** rows —
> six terminated/error records (a claude-tmux rehearsal, an enroll-fix instance, an accept-test, and
> three CI builders) plus the real one. Repointing all of them would have left six stale rows
> claiming to be VM 600, i.e. pointing at the live control plane; a reconciler acting on one of those
> would target ops-hub. **List first, then update only the row whose name is the ops-hub instance.**

```ruby
# 1. LOOK. Do not skip this step.
System::NodeInstance.where("config ->> 'cloud_instance_id' LIKE ?", "%/104").each do |i|
  puts "#{i.name}  status=#{i.status}"
end

# 2. Update ONLY the ops-hub row, by name.
i = System::NodeInstance.find_by(name: "ops-hub-instance-20260715231350-052f")
i.update!(config: i.config.merge("cloud_instance_id" => "dna/qemu/600"))

# 3. Confirm exactly one row claims /600.
System::NodeInstance.where("config ->> 'cloud_instance_id' = ?", "dna/qemu/600").pluck(:name)
```

Run the same three steps on the **dev plane** — both planes have driven this cluster, and the dev
plane is where the stale rows live.

**6c. The external watchdog** (rna VM 9001) needs no change: it keys on `TARGET_NAME=ops-hub`, not
the VMID. Confirm it is still reporting rather than assuming.

## Rollback

Reversible at every point. Before §4c nothing has changed but a flag and a timer. After that, run
the same commands with 600 and 104 swapped:

```bash
sudo qm stop 600 2>/dev/null; sudo qm set 600 --protection 0
sudo zfs rename local-zfs/local-data/vm-600-disk-0    local-zfs/local-data/vm-104-disk-0
sudo zfs rename local-zfs/local-data/vm-600-disk-1    local-zfs/local-data/vm-104-disk-1
sudo zfs rename local-zfs/local-data/vm-600-cloudinit local-zfs/local-data/vm-104-cloudinit
sudo mv /mnt/pve/dsm-data/snippets/600-user.yml /mnt/pve/dsm-data/snippets/104-user.yml
sudo mv /mnt/pve/dsm-data/snippets/600-meta.yml /mnt/pve/dsm-data/snippets/104-meta.yml
sudo mv /etc/pve/nodes/dna/qemu-server/600.conf /etc/pve/nodes/dna/qemu-server/104.conf
sudo mv /etc/pve/firewall/600.fw /etc/pve/firewall/104.fw
sudo sed -i -e 's/vm-600-/vm-104-/g' -e 's#snippets/600-#snippets/104-#g' \
            /etc/pve/nodes/dna/qemu-server/104.conf
sudo qm start 104 && sudo qm set 104 --protection 1
sudo mv /etc/powernode/qmstart-retry.armed.migrating /etc/powernode/qmstart-retry.armed
sudo systemctl start powernode-ops-hub-qmstart-retry.timer
```

**The data is never copied and never deleted at any point**, which is what makes this safe:
`zfs rename` is a metadata operation and the disks are the same blocks throughout. There is no
window in which ops-hub's `/persist` does not exist — worth stating explicitly, because
re-provisioning ops-hub *destroys* `/persist`, and that is the failure this procedure is designed to
avoid rather than risk.

## Deliberately not done here

- **VM 105 (`opn-1`, the firewall) is not touched, referenced, or relied on.** It is named in this
  document only as the reason for the move.
- **No `ipnode` cluster state changes** — no corosync edit, no HA resource, no watchdog arming. See
  `rcp-p1b-consensus-fencing-design.md` §6.2 for why the HA path was rejected.
- **VMID 104 is left free rather than reserved.** With both bands fenced, no allocator can reach it:
  dev floors at 500 and ops-hub at 9000. If a third, unfenced connection is ever added to this
  cluster, that assumption dies — fence it at creation.
