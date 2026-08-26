# Legacy encryption fallback audit — scope and gate

**Status:** scoping only. **No code changed.** Recorded 2026-08-26.

Commissioned while removing discovered legacy support from the PKI/federation surface. The
credential-encryption fallbacks are an *adjacent* domain: they look like the same kind of legacy
accommodation, but stripping them has a materially different failure mode, so they were split out
rather than swept along.

## Verdict

**Do not remove any of these until the census below returns zero.** Unlike a dead read path, these
fallbacks are the only way to *read back* data already written. If any ciphertext exists under the
old scheme, deleting its fallback makes that credential **permanently unrecoverable** — there is no
re-derivation and no backup path.

## The four sites

| # | Site | What it accommodates | Reachable in production? |
|---|---|---|---|
| 1 | `server/app/services/security/credential_encryption_service.rb:282` | `credentials.dig(:ai_encryption, :keys, …)` — key lookup falling back to the legacy AI credentials section | **Only where a Rails credentials file exists.** The self-hosted pivot-boot hub has no `config/credentials.yml.enc` / `master.key` (see the comment at :284-289); it uses `CREDENTIAL_ENCRYPTION_KEY_*` env vars. So unreachable on a deployed hub, reachable on any install that does ship credentials. |
| 2 | `…/credential_encryption_service.rb:330-332` | `validate_version` accepts `v1` alongside `v2` | **Yes** — this is the decrypt gate for any v1 blob still stored. |
| 3 | `…/credential_encryption_service.rb:344-346` | `ENV["AI_ENCRYPTION_KEY_<ID>"]` | **No.** It sits inside `generate_fallback_key`, which begins `return nil if Rails.env.production?`. Dev/test only. |
| 4 | `server/app/services/security/account_encryption_key_service.rb:52-58` | `decrypt` returns the blob unchanged when it is not a Vault transit blob — a pre-pepper plaintext passthrough | **Yes**, and it is a *different* mechanism from 1-3 (Vault transit pepper, not the v1/v2 envelope). Needs its own census. |

## What is already settled

`Ai::Security::CredentialEncryptionService` — the v1 producer named in the comment at :330 — **does
not exist anywhere in the tree.** The only surviving reference is that comment. So:

- No code path can write a v1 blob any more. The population is closed; it can only shrink.
- Site 3 is dead in production by its own guard and is the one safe removal of the four, though
  removing it alone buys little.

## The decisive census

`encrypt_value` emits `Base64.strict_encode64` of a JSON object whose **first** key is `version`
(`credential_encryption_service.rb:57-64`, `ENCRYPTION_VERSION = "v2"` at :24). Base64 of a fixed
prefix is itself a fixed prefix, so a stored blob's version is readable without decoding:

| Prefix | Meaning |
|---|---|
| `eyJ2ZXJzaW9uIjoidjIi…` | v2 — current |
| `eyJ2ZXJzaW9uIjoidjEi…` | v1 — legacy envelope |
| anything else | not a v2-shaped envelope; inspect individually |

The third bucket matters: v1 was written by a service that no longer exists, so its on-disk shape
is **not known to be the same envelope**. Counting only the `v1` prefix would under-report. Census
every blob-bearing column for "not v2-shaped", not for "v1-shaped".

Known producers to enumerate (from `encrypt_value` / `decrypt_value` call sites):

- `api/v1/email_settings_controller.rb:214,225`
- `api/v1/storage_providers_controller.rb:318`
- `api/v1/devops/integration_credentials_controller.rb:82-97`
- `ai/security/agent_identity_service.rb:174,178` (namespace `agent_identity`)
- `federation_partner.rb:242` — `outbound_token_encrypted` (namespace `federation`)

Per column, on the live DB (read-only):

```sql
SELECT count(*) FILTER (WHERE col LIKE 'eyJ2ZXJzaW9uIjoidjIi%') AS v2,
       count(*) FILTER (WHERE col NOT LIKE 'eyJ2ZXJzaW9uIjoidjIi%') AS not_v2,
       count(*)                                                     AS total
FROM   <table> WHERE col IS NOT NULL AND col <> '';
```

Site 4 needs a separate predicate — count values that fail `peppered_blob?`.

## Recommendation

1. Run the census across every column above. It needs read-only DB access (breakglass, revoked
   immediately after — see `scripts/breakglass.sh`).
2. If **every** column reports `not_v2 = 0` and site 4 reports no un-peppered values: remove sites
   1, 2 and 4, and the stale comment naming `Ai::Security::CredentialEncryptionService`.
3. If **any** column reports a non-zero count: do not remove anything. Re-encrypt those rows
   forward first (`rotate_encryption` already exists — `integration_credentials_controller.rb:82`),
   re-run the census, then remove.
4. Site 3 may be removed independently at any time; it is unreachable in production by its own
   guard.

Removing the fallbacks is the *last* step in either branch, never the first.
