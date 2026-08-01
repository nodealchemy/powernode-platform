# Native module builds cannot publish on ops-hub — cosign 3.x + restricted egress

> Status: diagnosed 2026-08-01, **not fixed**. Builds succeed and produce real
> artifacts; every one fails at signing and is silently retried forever.

## Symptom

A native module build dispatched on ops-hub reaches `awaiting_signature` and
stays there. Calling `NativeModuleBuildOrchestrator.advance!` does not finalize
it — it **re-dispatches**, incrementing `attempts`, so the batch loops and no
`NodeModuleVersion` is ever created. The `redis` module still has exactly one
version, from 2026-07-19.

Nothing in the batch or task surfaces the reason: the task reports
`status=complete` with `error_message` empty.

## Root cause

`cosign` on ops-hub is **v3.0.6**. It resolves a *signing config* from the
Sigstore TUF repository and **fails hard** when it cannot — even for key-based
(`--key`) signing, which needs no Sigstore service at all. ops-hub cannot reach
`tuf-repo-cdn.sigstore.dev` (egress is restricted by design):

```
Error: error getting signing config from TUF:
  Get "https://tuf-repo-cdn.sigstore.dev/14.root.json": dial tcp 34.117.62.14:443: i/o timeout
error during command execution: error getting signing config from TUF: ...
```

`System::ModuleSigningService` invokes (module_signing_service.rb:189):

```ruby
cmd = [ "cosign", "sign", "--yes", "--key", key_flag, ref_at_digest ]
```

No signing-config, so every invocation dies. `finalize_success!`
(native_module_build_orchestrator.rb:437) returns false, the module is queued
for retry, and the loop repeats.

**This is a regression from the cosign upgrade, not a configuration drift.**
Local signing was proven working on 2026-07-19 under cosign 2.x, where
key-based signing did not consult TUF.

## What is NOT the cause (each checked)

| hypothesis | finding |
|---|---|
| Signing mode fell back to `vault` | No — `MODE_EFFECTIVE=local`, as intended |
| Missing `oras` / `cosign` | No — both at `/usr/bin`, key present 0600 |
| TUF cache lost to tmpfs | No — `/root/.sigstore/tuf-repo-cdn.sigstore.dev` exists |
| Builder produced nothing | No — see below, the artifact is real |
| `ci_build_source_repo` unset | Harmless — `CI_BUILD_SOURCE_REPO_DEFAULT` covers it |
| Builder pool not wired (#42) | Stale — provider has a web base URL, builder leased and ran |

## The build itself is fine

The builder works. Its completed event carries a full result:

```
size            5459968
oci_digest      sha256:d2028cfd7e8384f6dc764c4752ad5745cf7ddef15cbdd9dfcdf0cca74374e12c
fsverity_root   sha256:2ca17f2a1ec8097d6f9fd6a02356c8f269060332bee225194014e553a282f79e
built_from_sha  fb6638eb7531caa2e2113ce00bd85d449f61ea36
```

Real digest, real fs-verity root, sane size, and `built_from_sha` matches the
requested commit. Only signing is broken.

## Fix (verified to clear the blocker, NOT applied)

cosign 3.x deprecates `--tlog-upload` and rejects it outright:

```
Error: --tlog-upload=false is not supported with --signing-config or
--use-signing-config. Provide a signing config with --signing-config without a
transparency log service, which can be created with `cosign signing-config create`
```

So the supported path is an explicit signing config with no transparency-log
service. Creating one offline works:

```bash
cosign signing-config create --out /persist/powernode-internal-ca/module-signing/signing-config.json
```

Adding `--signing-config <file>` to the cosign invocation **removes the TUF
failure** — verified on ops-hub. The TUF trusted-root fetch degrades to a
warning ("Continuing with individual targets") rather than a fatal error.

Implementation sketch, in the `local` branch only (the vault branch must stay
byte-identical for planes that have Vault):

```ruby
cmd = [ "cosign", "sign", "--yes" ]
cmd += [ "--signing-config", signing_config_path ] if signing_mode == "local"
cmd += [ "--key", key_flag, ref_at_digest ]
```

The config file belongs beside the local key under
`/persist/powernode-internal-ca/module-signing/` (durable), generated on demand
by `System::ModuleSigningKey`-style `ensure!` so a fresh plane self-provisions.

**One caveat.** The verification above was done with an ad-hoc cosign call that
skipped the registry auth the service performs (`with_registry_docker_config` /
`oras login`), so it then failed on registry token access. That is an artifact
of the probe, not of the fix — but the fix has NOT been proven end-to-end
through `ModuleSigningService`, and should be before it is trusted.

## Secondary findings

- **`advance!` retries silently.** A signing failure sets `entry["error"]`, but
  the retry path clears it, so an operator polling the batch sees
  `state=dispatched, error=nil` and no indication anything is wrong. Repeated
  calls just burn builder leases. Surfacing the last failure across a retry
  would have made this a one-minute diagnosis instead of an afternoon.
- **A batch left in `awaiting_signature` is swept** by
  `CiRunnerLeaseSweepService`, so a failing batch can loop unattended.

## Reproducing

```ruby
# on ops-hub, as root
acct = Account.find("019f6835-63d4-7816-96a7-26774ce788f0")
b = System::ModuleBuildBatch.create_for(
      account: acct, plan: [{ module: "redis", oci_ref: "<7-char sys sha>" }],
      trigger: "manual", base_sha: SHA, head_sha: SHA, source_repo: nil)
System::NativeModuleBuildOrchestrator.dispatch!(batch: b)
# ... wait ~80s, then:
System::NativeModuleBuildOrchestrator.advance!(batch: b)   # re-dispatches, never finalizes
```

Read `task.events` — not `task.result`, which is empty — for the builder's
actual output:

```ruby
Array(task.events).reverse.find { |e| e["type"] == "completed" }["result"]
```
