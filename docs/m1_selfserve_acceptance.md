# M1 Self-Serve Acceptance Checklist

Manual smoke checklist for the M1 self-serve activation funnel ($49/mo Pro
Cloud SaaS). Run after every M1 change to confirm the funnel is wired
end-to-end and the four sliced systems (foundation, ProCloudProvider,
billing, frontend polish) are coordinating correctly.

## Pre-flight

Before running through the checklist:

1. **Apply pending migrations on dev DB.**
   ```
   cd server && bundle exec rails db:migrate
   ```

2. **Stale plan rows** — `db/seeds/saas_plans_seed.rb` uses `find_or_create_by!`,
   which does NOT update existing rows to add the new `limits` keys
   introduced by Slice C. Without this, free-tier QuotaGuard treats all
   accounts as unlimited and the paywall step at the end of the
   checklist will not fire. Mitigation:
   ```
   cd server && bundle exec rails runner "
     ::SaasPlan.find_each do |p|
       limits = case p.slug
                when 'free'   then { 'max_node_instances' => 1, 'max_monthly_provisioning_usd' => 20 }
                when 'pro_cloud' then { 'max_node_instances' => 50, 'max_monthly_provisioning_usd' => 500 }
                else p.limits
                end
       p.update!(limits: limits) if p.limits != limits
     end
   "
   ```

3. **Vultr API credentials** — Slice B reads from
   `System::ProviderCredential` (account-scoped, with platform-pool
   fallback). For the platform-pool fallback to work in dev, register a
   Vultr API key on the canonical `Pro Cloud` provider via the
   credential UI (Settings → Cloud Credentials) before running the test.
   For account-isolation testing, register a separate cred under the
   test account.

4. **Stripe test card** — checkout uses the standard
   `4242 4242 4242 4242` test card.

5. **Worker rollup endpoint** — `worker/app/jobs/billing_provisioning_meter_job.rb`
   POSTs to `/api/v1/internal/billing/provisioning/meter/rollup` which
   does NOT exist server-side yet. Daily rollup will fail silently. Open
   follow-up. Live-spend display in step 6 below uses on-the-fly
   aggregation from `Billing::ProvisioningUsageRecord`, which works
   without the rollup endpoint.

## Checklist

- [ ] **Sign up → checkout → land on /new**
  - Visit `/auth/register` as a fresh email.
  - Complete the multi-step signup (email + password + name) and the
    embedded Stripe checkout (free plan card).
  - Confirm post-checkout redirect to `/new` (the provisioning chat).
  - Verify `Account.after_create_commit` ran by querying the dev DB:
    ```
    rails runner "a = Account.last; puts \"providers=#{System::Provider.where(account: a).count} regions=#{System::ProviderRegion.where(account: a).count} types=#{System::ProviderInstanceType.where(account: a).count} templates=#{System::NodeTemplate.where(account: a).count}\""
    ```
    Expected: `providers=1 regions=2 types=3 templates=7`.

- [ ] **Type Discord bot brief → Brief Card populates**
  - In the chat input, paste:
    > I want to run my Discord moderation bot 24/7 on a small VM. It's a
    > side project, I don't need anything fancy — just $5/mo on a 1 vCPU box.
  - Confirm the AI response captures intent="Run my Discord bot 24/7",
    use_case mentions "Discord bot", scale.initial=1, regions=["us-east-1"],
    budget_cap_usd_monthly≈10.
  - The Brief Card on the right pane should populate with these values.

- [ ] **Approve → 1-step plan with $5/mo cost estimate**
  - Click "Open Plan" once it surfaces.
  - Plan modal should show:
    - **1 step** in the topology (`provision_full_stack`) — Slice D
      step-collapse pass merged 3 redundant sequential steps into 1.
    - Cost estimate **$5.04/mo** (one Pro Cloud `vc2-1c-1gb` in
      `us-east-1`).
    - Risk severity: **low**.
  - Verify via API:
    ```
    curl -H "Authorization: Bearer $TOKEN" /api/v1/ai/missions/$MISSION_ID | jq '.data.plan.dag.step_count'
    ```
    Expected: `1`.

- [ ] **Execute → instance running on Vultr within 90s**
  - Click "Approve & Provision".
  - Watch ExecutionPill bottom-right; the step transitions
    `pending → running → completed`.
  - Confirm a Vultr instance was created:
    ```
    curl https://api.vultr.com/v2/instances -H "Authorization: Bearer $VULTR_KEY" | jq '.instances | length'
    ```
    Or check the dev DB:
    ```
    rails runner "puts System::NodeInstance.last.attributes.slice('id','status','provider_instance_id','created_at')"
    ```
    Expected: `status='running'` within ~90s of approve click.
  - Verify a `Billing::ProvisioningUsageRecord` was created:
    ```
    rails runner "puts ::Billing::ProvisioningUsageRecord.last.attributes.slice('event','metered_at','status')"
    ```
    Expected: `event='running'`, `status='pending'` (rolled up later).

- [ ] **Try second instance → UpgradeRequiredCard renders**
  - Back to `/new`, type a second prompt:
    > Spin up another bot host alongside the first one.
  - Drive through brief → plan review → Approve.
  - On click, the response should be `402 upgrade_required`. Frontend
    should render `UpgradeRequiredCard` (Slice D component) instead of
    the execution view, with copy referencing free-tier limits and an
    upgrade CTA.

- [ ] **Subscription's daily spend reflects usage**
  - Navigate to Settings → Billing.
  - Confirm the live spend tracker shows ≈$5.04/mo accumulating (or the
    pro-rated daily share) for the running instance. Calculation source:
    on-the-fly aggregation over `Billing::ProvisioningUsageRecord` since
    the daily rollup endpoint is not yet wired (see pre-flight item 5).
  - The cost-cap progress bar in the Brief Card should also reflect
    the same value (Slice D `CostCapGuard` reads the same source).

## Negative-path coverage (recommended)

- [ ] Disable the Vultr API in `System::ProviderCredential` and approve a
      plan — provisioning should fail-closed and surface a friendly
      "credentials missing or invalid" toast (no half-billed records).
- [ ] Force `Billing::ProvisioningQuotaGuard` to return `over_limit`
      (e.g., manually set `current_usage.node_instance_count = 1` for a
      Free account) — Approve should immediately render
      `UpgradeRequiredCard` without contacting the cloud API.
- [ ] Trigger step-collapse with a non-redundant 3-step plan (e.g.,
      compute + db + network) — collapse should NOT merge them; review
      modal shows 3 separate steps.

## Cross-references

- Foundation slice (Account hook + bootstrap):
  `extensions/system/server/spec/services/system/account_bootstrap_service_spec.rb`
- ProCloudProvider (Vultr adapter):
  `extensions/system/server/spec/services/system/providers/pro_cloud_provider_spec.rb`
- Billing (UsageRecord + QuotaGuard + MeterService):
  `extensions/business/server/spec/services/billing/`
- Frontend polish (CostCapGuard + step-collapse + UpgradeRequiredCard):
  `frontend/src/features/ai/provisioning/__tests__/`
- Activation-funnel UI flow e2e:
  `e2e/provisioning/discord-bot-activation.spec.ts`
