# Secret Storage Backends — Vault ⇄ Database, Global Toggle + Migration

> Status: **Design / proposed** (not yet implemented). Last updated 2026-06-20.
>
> A single secret-access seam with **two interchangeable backends** — HashiCorp **Vault** and
> **DB-encrypted** storage — chosen by a **global toggle**, with **bidirectional migration**
> between them. Lets an operator run with Vault (recommended) or fall back to DB-encrypted
> storage (lighter infra for small/self-hosted installs) and move existing secrets either way
> without re-entering them. Consumed by the [setup wizard](setup-wizard-design.md).

## 1. Goals

1. **Global enable/disable of Vault** — one setting selects the active secret backend.
2. **DB-encrypted fallback** — when Vault is off, secrets live in the DB, encrypted at rest
   (authenticated encryption + per-account pepper), never plaintext.
3. **Bidirectional migration** — move all existing secrets Vault→DB or DB→Vault, verified, with
   no re-entry, then flip the toggle.
4. **Backend-agnostic callers** — credential models / services read & write through one seam and
   don't care which backend is active.
5. Honor the **crypto-safety rules** (CLAUDE.md): never output/log secret material; audit every
   key operation; generation stays in Vault / the platform's Vault-backed key service when Vault is on.

## 2. Reuse-first inventory (what already exists)

| Piece | Path | Role |
|---|---|---|
| Vault KV/PKI/Transit clients | `server/app/services/security/vault_client.rb`, `vault_pki_client.rb`, `vault_transit_client.rb` | Vault backend internals |
| Vault credential provider | `server/app/services/security/vault_credential_provider.rb` | Existing Vault read/write abstraction |
| Vault model concern | `server/app/models/concerns/vault_credential.rb` | Models that store secrets in Vault |
| **Existing migration service** | `server/app/services/security/vault_migration_service.rb` | Generalize → bidirectional |
| DB-encryption (the other backend) | `server/app/models/concerns/account_peppered_encryption.rb` + Rails `encrypts` (`user.rb`, `ai/data_source_credential.rb`, `external_agent.rb`) | DatabaseBackend internals |
| Vault-configured detection | `server/config/initializers/vault.rb` (`vault_configured?` from ENV **or** `db_config`) | Basis for the toggle |
| Infra/Vault admin config | `server/app/controllers/concerns/admin_settings/infrastructure_config_actions.rb` | Where the toggle + addr/creds are set |

So two backends and a migration service already exist in pieces; what's missing is the
**unifying facade**, a **first-class toggle**, and making migration **bidirectional + driven
from settings/the wizard**.

## 3. Architecture: one facade, two backends

```
Security::SecretStore                      # the only thing callers touch
  .write(scope:, key:, value:)             # scope = account + logical bucket
  .read(scope:, key:)
  .delete(scope:, key:)
  .backend                                 # :vault | :database (resolved from the toggle)

  ├── VaultBackend       (wraps VaultClient / VaultCredentialProvider / Transit)
  └── DatabaseBackend    (wraps account_peppered_encryption on a `secrets` table /
                          the existing encrypted columns)
```

- **Selection** is resolved once per request from the global toggle (§4): `vault_enabled &&
  vault_reachable? ? VaultBackend : DatabaseBackend`. A hard failure to reach Vault when it's
  enabled is an error (fail-closed), **not** a silent fallback to DB — silently downgrading
  secret storage would be a security surprise.
- Credential models adopt the seam incrementally: `vault_credential` and the `encrypts`-based
  models both become thin users of `SecretStore` rather than committing to one backend.
- `scope` namespaces secrets by account + bucket so the same logical key (`smtp.password`)
  lives at a deterministic path in either backend.

## 4. The global toggle

- Stored as an **infrastructure setting** (extend the existing `db_config` /
  `infrastructure_config_actions` surface; mirror to `AdminSetting` for fast reads):
  `secret_backend = "vault" | "database"`.
- Reuses the existing `vault_configured?` check — the toggle can only be set to `vault` when
  Vault address + AppRole creds are present and a health probe passes.
- Effective at runtime (no redeploy): `SecretStore.backend` reads the setting (cached, busted on
  change). Changing the toggle **does not move data** — that's migration (§5); the UI refuses to
  flip the toggle while secrets exist in the other backend until a migration has run.

## 5. Migration service (bidirectional)

Generalize `vault_migration_service` → `Security::SecretMigrationService`:

```
SecretMigrationService.run(from: :vault|:database, to: :database|:vault, dry_run:)
```

- **Enumerate** every secret in the source backend (via a registry of secret-bearing
  models/scopes — each credential model declares its secret keys).
- **Copy** each into the target backend; **verify** by round-trip read (compare ciphertext-free:
  decrypt-and-compare in memory, never logged).
- **Idempotent + resumable**: per-secret migration state (`migrated_at` marker) so a re-run skips
  done items; a crash mid-run is safe to resume.
- **Flip** the toggle only after 100% verified; optionally **purge** the source copies (explicit,
  after a retention window — disabled by default so a rollback is possible).
- Runs as a **worker job** for large sets (per worker-architecture rules — dispatched via the
  API, executed by the worker), with progress surfaced to the UI.
- **Crypto-safety:** every secret op is written to the audit log; secret *values* are never
  logged, never placed in job args/errors/traces — only opaque references (scope + key).

## 6. Wizard / settings integration

- The setup wizard's **secret-storage step** offers: *Vault* (collect addr + AppRole, health-
  probe) or *DB-encrypted* (default for installs without Vault).
- Changing the backend later (Settings → Infrastructure) with existing secrets presents a
  **migration confirm**, then triggers `SecretMigrationService` as a job.
- This is also where the email-secret decision from the wizard lands: email/SMTP secret →
  `SecretStore.write` → whichever backend is active.

## 7. Security model

- **DB backend** uses authenticated encryption (Rails `encrypts`, AES-GCM) keyed by the master
  key **plus a per-account pepper** (`account_peppered_encryption`) — compromise of the DB alone
  does not yield plaintext.
- **Fail-closed**: Vault-enabled + unreachable ⇒ error, never silent DB fallback.
- **No plaintext at rest or in transit logs**; migration verifies in memory only.
- **Audit** every generate/import/migrate/revoke (existing crypto-safety requirement).
- Key *generation* still happens in Vault / the platform's Vault-backed key service when Vault is on; the DB backend is
  for storage of already-collected secrets, not for generating signing/key material via CLI.

## 8. Phased plan

- **Phase A — Facade:** introduce `Security::SecretStore` + `VaultBackend`/`DatabaseBackend`
  wrapping the existing clients/concerns; route one model (e.g. SMTP/email creds) through it. No
  behavior change for existing Vault users.
- **Phase B — Toggle:** `secret_backend` setting + `vault_configured?`-gated UI; `SecretStore`
  honors it; fail-closed semantics.
- **Phase C — Migration:** generalize `vault_migration_service` to bidirectional + verified +
  resumable worker job; settings/wizard trigger.
- **Phase D — Adopt:** migrate remaining credential models onto `SecretStore` (incremental).

## 9. Open questions

1. Secret registry — explicit per-model declaration of secret keys vs. a scan of
   `encrypts`/`vault_credential` usages to enumerate what migrates?
2. Purge-after-migrate — default off (keep source for rollback) for how long, and who confirms
   the purge?
3. Per-account vs. global toggle — is the backend a single global choice, or selectable per
   account/tenant? (Proposed: global for now; the `scope` already carries account so per-account
   is a later extension.)

---

Related: [setup-wizard-design.md](setup-wizard-design.md) (consumes the toggle + migration),
CLAUDE.md "Cryptographic Material Safety" (the rules this design must satisfy).
