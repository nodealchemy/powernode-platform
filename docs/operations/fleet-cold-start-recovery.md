# Fleet node cold-start recovery (expired bootstrap token / lost PKI)

**Audience:** operators of long-lived composed instances (control-plane hubs, dev cells,
anything not disposable). **Origin:** the 2026-07-28 VM restart incident where a pool builder
never came back — it looped forever on `bootstrap: enroll: validation failed (422): invalid or
expired bootstrap token`, pre-pivot, with no IP, no SSH, and no guest agent.

## The enrollment lifecycle (what protects you, and its edge)

1. **First boot only:** the agent enrolls with a **one-shot, short-lived bootstrap token**
   delivered by the provisioning seed. Success writes an mTLS node identity to the persisted
   PKI directory (`/persist/var/lib/powernode/pki/`).
2. **Every later boot:** `bootstrap()` adopts the on-disk identity *before any discovery* — a
   valid cert on disk short-circuits enrollment entirely. The bootstrap token is never needed
   again.
3. **Rotation:** the node cert is valid ~90 days (`InternalCaService::DEFAULT_TTL_SECONDS`) and
   a rotation goroutine refreshes it via `POST /enroll/refresh`, authenticated by the
   *existing* cert — again, no token involved.

So an enrolled node survives reboots indefinitely. The failure window is narrow but real:

- the node is **powered off (or its agent dead) continuously past the cert's `NotAfter`**, or
- the persisted PKI directory is **lost or corrupted** (disk replacement, accidental
  `/persist` wipe, re-provision).

In either case the agent falls back to first-boot enrollment, presents its long-expired
one-shot token, and loops on 422 forever. The VM looks "running" to the hypervisor but never
pivots, never gets an address, and burns its full CPU allocation doing nothing.

## Detection

- Hypervisor shows the VM running but with **no guest agent and no IP**.
- The 422 loop is visible only on the **serial console** (read-only attach, e.g. on
  QEMU/Proxmox: `socat -u UNIX-CONNECT:/var/run/qemu-server/<vmid>.serial0 -`).
- On the platform side the instance's heartbeat goes stale and never recovers across restarts.

## Recovery

**Supported path today: re-provision the instance.** ⚠️ Re-provisioning **destroys
`/persist`** — for any node with valuable persisted state this is a last resort, not a
routine fix. For pool members (builders, ephemeral cells) it is the correct and cheap answer:
destroy and let the pool replenish.

**Manual re-arm (advanced, durable nodes only).** There is currently **no wired re-arm path**
— `BootstrapToken.issue!` is invoked only at provision/seed time. The pieces exist for an
operator-driven recovery and have been used in anger, but treat this as a procedure to
*verify in a drill before you need it*:

1. On the platform, issue a fresh token bound to the existing instance record
   (`BootstrapToken.issue!(node_instance: …)` from a console).
2. Regenerate the provisioning seed (cidata ISO / fw_cfg identity) so it carries the new
   token, and re-present it to the VM (on Proxmox this means regenerating the seed artifact —
   a bare `stop`+`start` only re-presents the *same* stale seed).
3. Cold-start the node and watch the serial console for enrollment success.
4. If the instance's registry row no longer exists (platform data loss), re-arm is not
   possible: the node has no identity to re-bind. Re-provision, or re-enroll it as a new
   instance and re-attach its storage.

## Prevention (do these, in order of leverage)

- **Never leave a durable node powered off for weeks.** The cert only rotates while the agent
  runs; downtime consumes the 90-day budget silently.
- **Before planned long downtime,** check the node cert's `NotAfter` and restart the agent
  once to force a fresh rotation window.
- **Monitor cert expiry fleet-wide** — a sensor emitting an event when any node identity has
  <21 days remaining turns this whole failure class into a routine ticket. (Not yet
  implemented; tracked as campaign work.)
- **Protect `/persist`** on durable nodes: hypervisor-level protection flags, and never
  re-provision as a "fix" without confirming what lives there.
