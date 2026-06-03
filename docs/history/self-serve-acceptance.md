# M1 Self-Serve Acceptance

> **ARCHIVED 2026-06-03** — Preserved for historical context. See current docs for current state.
>
> Status: archived. This is a point-in-time M1 milestone checklist for the **self-serve activation funnel**, which depends on the private **business** (billing) and **system** extensions. It is **not part of core mode** (single-user self-hosted, business/trading absent) and is not an evergreen base runbook. Retained only as a record of the M1 slice acceptance flow.
>
> When to use this runbook: smoke-checking the M1 self-serve activation funnel after any change touching the four sliced systems (foundation, ProCloudProvider, billing, frontend polish).

## Table of Contents

- [Prerequisites](#prerequisites)
- [When to use this](#when-to-use-this)
- [Pre-flight](#pre-flight)
- [Procedure — happy path](#procedure--happy-path)
- [Negative-path Coverage](#negative-path-coverage)
- [Verification](#verification)
- [Rollback](#rollback)
- [Troubleshooting](#troubleshooting)
- [Cross-references](#cross-references)

## Prerequisites

- Local dev DB up-to-date (apply pending migrations — see [Pre-flight](#pre-flight))
- Vultr API credentials registered on the canonical Pro Cloud provider via Settings → Cloud Credentials
- Stripe test mode available (test card `4242 4242 4242 4242`)
- Worker service running
- `business` and `system` extensions enabled (M1 funnel is extension-gated)

## When to use this

- After any change to the M1 funnel (`extensions/system/server/services/system/account_bootstrap_service*`, ProCloudProvider, billing meter / quota guard, frontend provisioning polish).
- Before promoting a release branch carrying M1 changes to `master`.
- After config edits to the `pro_cloud` SaasPlan limits.

## Pre-flight

1. **Apply pending migrations on the dev DB:**

   ```bash
   cd server && bundle exec rails db:migrate
   ```

2. **Refresh stale plan rows.** `extensions/business/server/db/seeds/saas_plans_seed.rb` uses `find_or_create_by!`, which does NOT update existing rows to add the new `limits` keys introduced by Slice C. Without this, free-tier `QuotaGuard` treats all accounts as unlimited and the paywall step below will not fire.

   ```bash
   cd server && bundle exec rails runner "
     ::SaasPlan.find_each do |p|
       limits = case p.slug
                when 'free'      then { 'max_node_instances' => 1,  'max_monthly_provisioning_usd' => 20  }
                when 'pro_cloud' then { 'max_node_instances' => 50, 'max_monthly_provisioning_usd' => 500 }
                else p.limits
                end
       p.update!(limits: limits) if p.limits != limits
     end
   "
   ```

3. **Vultr API credentials.** Slice B reads from `System::ProviderCredential` (account-scoped, with platform-pool fallback). For the platform-pool fallback to work in dev, register a Vultr API key on the canonical `Pro Cloud` provider via Settings → Cloud Credentials before the test. For account-isolation testing, register a separate cred under the test account.

4. **Stripe test card.** Checkout uses the standard `4242 4242 4242 4242` test card.

5. **Worker rollup endpoint.** `worker/app/jobs/billing_provisioning_meter_job.rb` POSTs to `/api/v1/internal/billing/provisioning/meter/rollup` which does NOT yet exist server-side. Daily rollup fails silently. Live-spend display in step 6 uses on-the-fly aggregation over `Billing::ProvisioningUsageRecord`, which works without the rollup endpoint. Track this as a follow-up.

## Procedure — happy path

- [ ] **Sign up → checkout → land on `/new`**
  - Visit `/auth/register` as a fresh email.
  - Complete the multi-step signup (email + password + name) and the embedded Stripe checkout (free plan card).
  - Confirm post-checkout redirect to `/new` (the provisioning chat).
  - Verify `Account.after_create_commit` ran:

    ```bash
    rails runner "a = Account.last; puts \"providers=#{System::Provider.where(account: a).count} regions=#{System::ProviderRegion.where(account: a).count} types=#{System::ProviderInstanceType.where(account: a).count} templates=#{System::NodeTemplate.where(account: a).count}\""
    ```

    Expected: `providers=1 regions=2 types=3 templates=7`.

- [ ] **Type Discord-bot brief → Brief Card populates**
  - In the chat input, paste:
    > I want to run my Discord moderation bot 24/7 on a small VM. It's a side project, I don't need anything fancy — just $5/mo on a 1 vCPU box.
  - Confirm the AI response captures intent="Run my Discord bot 24/7", use_case mentions "Discord bot", scale.initial=1, regions=["us-east-1"], budget_cap_usd_monthly ≈ 10.
  - The Brief Card on the right pane should populate with these values.

- [ ] **Approve → 1-step plan with $5/mo cost estimate**
  - Click "Open Plan" once it surfaces.
  - Plan modal should show:
    - **1 step** in the topology (`provision_full_stack`) — Slice D step-collapse pass merged 3 redundant sequential steps into 1.
    - Cost estimate **$5.04/mo** (one Pro Cloud `vc2-1c-1gb` in `us-east-1`).
    - Risk severity: **low**.
  - Verify via API:

    ```bash
    curl -H "Authorization: Bearer $TOKEN" /api/v1/ai/missions/$MISSION_ID | jq '.data.plan.dag.step_count'
    ```

    Expected: `1`.

- [ ] **Execute → instance running on Vultr within ~90s**
  - Click "Approve & Provision".
  - Watch the bottom-right ExecutionPill; the step transitions `pending → running → completed`.
  - Confirm a Vultr instance was created:

    ```bash
    curl https://api.vultr.com/v2/instances -H "Authorization: Bearer $VULTR_KEY" | jq '.instances | length'
    ```

    Or check the dev DB:

    ```bash
    rails runner "puts System::NodeInstance.last.attributes.slice('id','status','provider_instance_id','created_at')"
    ```

    Expected: `status='running'` within ~90s of the approve click.
  - Verify a `Billing::ProvisioningUsageRecord` was created:

    ```bash
    rails runner "puts ::Billing::ProvisioningUsageRecord.last.attributes.slice('event','metered_at','status')"
    ```

    Expected: `event='running'`, `status='pending'` (rolled up later).

- [ ] **Try a second instance → UpgradeRequiredCard renders**
  - Back to `/new`, type a second prompt:
    > Spin up another bot host alongside the first one.
  - Drive through brief → plan review → Approve.
  - On click, the response should be `402 upgrade_required`. The frontend should render `UpgradeRequiredCard` (Slice D component) instead of the execution view, with copy referencing free-tier limits and an upgrade CTA.

- [ ] **Subscription's daily spend reflects usage**
  - Navigate to Settings → Billing.
  - Confirm the live spend tracker shows ≈$5.04/mo accumulating (or the pro-rated daily share) for the running instance. Source: on-the-fly aggregation over `Billing::ProvisioningUsageRecord` since the daily rollup endpoint is not yet wired (see pre-flight item 5).
  - The cost-cap progress bar in the Brief Card should reflect the same value (Slice D `CostCapGuard` reads the same source).

## Negative-path Coverage

- [ ] **Missing / invalid credential.** Disable the Vultr API in `System::ProviderCredential` and approve a plan — provisioning should fail-closed and surface a friendly "credentials missing or invalid" toast (no half-billed records).
- [ ] **Quota guard.** Force `Billing::ProvisioningQuotaGuard` to return `over_limit` (e.g. manually set `current_usage.node_instance_count = 1` for a free account) — Approve should immediately render `UpgradeRequiredCard` without contacting the cloud API.
- [ ] **Step-collapse boundary.** Trigger a non-redundant 3-step plan (compute + db + network) — collapse should NOT merge them; the review modal should show 3 separate steps.

## Verification

After the checklist passes:

- Final state: one running `System::NodeInstance`, one `Billing::ProvisioningUsageRecord` with `event='running'`.
- No 500s in `journalctl -u powernode-backend@default --since "10 minutes ago"`.
- Sidekiq dashboard shows no failed `Billing::ProvisioningMeterJob` items (silent rollup failures are acceptable; see pre-flight item 5).

## Rollback

If the funnel breaks mid-test:

1. Destroy the Vultr instance manually via the Vultr API or admin UI.
2. Delete the `System::NodeInstance` and corresponding `Billing::ProvisioningUsageRecord` in dev:
   ```bash
   rails runner "System::NodeInstance.find_by(provider_instance_id: '...').destroy"
   ```
3. Reset the dev account's spend cap by clearing `Billing::ProvisioningUsageRecord` for the account.
4. Re-run pre-flight steps before retrying.

## Troubleshooting

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Brief Card never populates | AI provider quota exhausted | Check `Ai::Provider.find_by(name: 'pro_cloud').current_quota_usage` |
| Approve produces 5xx | Worker not running | `sudo systemctl status powernode-worker@default` |
| Vultr instance never created | Provider credentials missing | Re-register Vultr API key per pre-flight item 3 |
| UpgradeRequiredCard never fires | Stale plan limits | Re-run pre-flight item 2 |

## Cross-references

- Foundation slice (Account hook + bootstrap): `extensions/system/server/spec/services/system/account_bootstrap_service_spec.rb`
- ProCloudProvider (Vultr adapter): `extensions/system/server/spec/services/system/providers/pro_cloud_provider_spec.rb`
- Billing (UsageRecord + QuotaGuard + MeterService): `extensions/business/server/spec/services/billing/`
- Frontend polish (CostCapGuard + step-collapse + UpgradeRequiredCard): `frontend/src/features/ai/provisioning/`
- Activation-funnel UI flow e2e: `e2e/provisioning/discord-bot-activation.spec.ts`

---

## Related runbooks

- [production-deployment.md](../operations/production-deployment.md) — Initial platform install
- [ai-operations.md](../operations/ai-operations.md) — Mission and worker procedures
- [data-sources.md](../operations/data-sources.md) — External API quota patterns

## Materials previously at

- `docs/m1_selfserve_acceptance.md`
- `docs/operations/self-serve-acceptance.md` (archived here 2026-06-03)

_Last verified: 2026-06-03_
