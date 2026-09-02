# APO campaign — bulk review after batches 1–3 (2026-09-02)

Session work-6a drove dev-improve batches 1–3 (39 tasks closed as passed, 2 parked by the
platform guardrail with their commits standing) and the campaign
"Autonomous Project Operations (scaling + DR)" (`01a0609d-d6a1-796f-8c29-a3e894207dc1`,
16 increments recorded). Everything is on `dev-loop/dev-improve` in both repos, UNPUSHED,
UNDEPLOYED. `scripts/pattern-validation.sh` 52/52; the branch-health spec set is green.

Rulings are grouped below. Reply with the numbers you approve or veto.
## Rulings needed to CLOSE parked tasks
1. IMP-43e94c9d46d4 (APO-1d) — commits 50693e06 + 493d4903 stand; task parked by the scope guardrail because the prose sweep edited docs/runbooks/vault-credential-restoration.md (protected *credential*). Ruling: accept the 2-line doc correction → close as passed.
2. IMP-f86b6be57e74 (UserToken snapshot) — fixed in core 0f23a965c + business c41e4a0; parked on extensions/private/business/.../impersonation_service_spec.rb. Ruling needed.
3. IMP-6477865679f4 (roles:standardize deletion) — fixed in a730a1663; parked on server/app/services/permissions/role_grant_reconciler.rb. Ruling needed.
4. IMP-70f737718cef — needs `platform.dev_update_task` added to the production instance grant (operator-only; mode: add).
5. IMP-439d31353f9b / IMP-74995230ed5b — blocked-by-design; APO-1a..1e now carry 439d's sequencing. Ruling: close 439d as superseded by APO-1a/1b/1e; 7499 stays until its three stale prerequisites are re-verified.

6. IMP-efc4b9c2d96b (provider-credential SDK guard) — commit 35b7ab3e stands; parked by the guardrail because the task's own target file is provider_credentials_controller.rb (protected *credential*). Ruling: close as passed.

## Assumed rulings pinned into task directions (veto if wrong)
- Additive DR auto-applies within bounds; reaps/terminations always approval-gated.
- DB promotion auto only when primary provider-confirmed down AND replica lag under bound; else approval.
- Platform self-scaling reconciles target_replicas for NON-hub PlatformDeployments only.
- Provider registry guard now; aws-sdk-ec2 / google-cloud-compute / fog-openstack gems deferred.
- Load balancer = Traefik (existing ingress) + anycast VIP/BGP later; no new LB component.
- cert_rotate implemented as revoke-superseded (server cannot re-issue: key lives on the node); policy stays require_approval.

## Design questions surfaced by reviewers (no action taken)
- Should streamable-HTTP tools/list advertise the richer outputSchema? It hard-codes {type: object} for 2025-06-18+ clients by stated rationale (streamable_http_controller.rb:975; pinned by structured_tool_output_spec.rb:94).
- APO-1e prerequisites: action_category nil on all 596 new declarations (resolver defaults to require_approval); FederationTool overrides #execute without super (known-inert); mutating/read split unpinned; private-bundle extra tool map has no acknowledgement channel now the snapshot is empty.
- Six skill-actuated lanes return applied:false by shape and are now de-scored like the applier-less ones; the fix (skill-actuated bindings reporting actuation) is deferred at fleet_autonomy_service.rb:975-985.
- Provider specs: the direction "replace self-skipping specs" rests on a false premise — .gitea/workflows/ci.yaml:327 has a provider-specs lane that runs them with the gems; left as-is.
- The MCP catalog now embeds a bundle-dependent "operable provider types" sentence; stable while the freshness gate pins the public bundle.
- Retained hard abort in AttachServicesMode still strands unrelated later services (documented + pinned); narrowing to the true dependent closure is a separate change.
- topoSort skips an edge whose target is absent while writeDependencyDirectives still renders it (pre-existing asymmetry).

## Held-back tasks (not scheduled)
- Private business extension: IMP-4c0a826ad21a (marketplace set_template), IMP-b54e49ddfc40 (billing quota guard vs idempotency), IMP-01b1e152f667 (BillingBridge meter seam).
- Protected permissions path: IMP-222dd9bce564 (role-grant reconciler revocation reversal).
- Auth-adjacent core (scheduled later, will park if guardrail fires): IMP-1635cb7fa768 (role assignment), IMP-6a112bebbe9f (factory global role).

## Added during batch 2
- CLAUDE.md:111 "Extension Isolation" now describes only the core half; gate #9 also blocks extension→other-extension references since 847a185a9. Ruling: update the CLAUDE.md sentence (I did not edit CLAUDE.md on my own).
- .claude/hooks/core-purity-baseline.local.txt is gitignored and holds 9 of 10 grandfathered entries — it does not travel to other checkouts; any other maintainer clone with private extensions will be hard-blocked on those 8 files until they run scripts/generate-core-purity-baseline.sh. Ruling: accept, or move the private entries into a tracked-but-encrypted/ hashed form.
- The ::Billing:: constant reference in extensions/system provisioning_service.rb is NOT caught by any name-token gate (it is a core→business coupling through a core bridge); closes only with the BillingBridge meter seam task IMP-01b1e152f667 (held: touches extensions/private/business).
- Instance-pool #update ungated ceiling (filed+approved IMP-24daa05e7a22); replenish deliberately ungated (ruling recorded in 4b9a11c5) — confirm.
- APO-2b thresholds are ENV+constant pending APO-2e (IMP-ca485128072e) which moves all sensor thresholds to DB config and implements the two documented sensor-config verbs.
- PRODUCT FORK (offer 01a0619a-431e-7d93-bca4-9b9de2117399, left pending): wire-or-retire system_nodes.lifecycle_class. No REST/MCP surface sets it; only pool replenishment copies pool.lifecycle_class as a snapshot. WIRE = short-circuits must read the pool (snapshot can drift); RETIRE = default must become NULL in the same change (NOT NULL "persistent" is wrong for pool members). Recommendation: RETIRE the node column once the pool is the authoritative reader; keep the pool column.
- DEPLOY SIZING for APO-1c (676de7b8): with no operator policy rows, InterventionPolicyService defaults to require_approval, so all 14 requires_approval executors will PARK an approval on their first MCP/REST/Concierge call after deploy (architecture create/update, expose service publicly/TCP, federation acceptance, fulfill capability request, multi-tenant isolation, relocate workload, service-discovery compose, …). No default rows are seeded for the 11 new categories (deliberate). Ruling: seed auto_approve/notify rows for the read-shaped ones before deploying, or accept the parking.
- PlatformDeployExecutor declares no requires_approval and stays ungated on the direct path (policy call).
- SdwanFederationComposeExecutor is registered as approval-gated (engine.rb) but its descriptor declares no flag — pre-existing inconsistency; pick one.
- APO-1f filed: parked executors return success:false today (kept so composed plans stop); the envelope + plan resume is the fix.
- docs/reference/system-extension-evaluation-2026-09-02.md and the gap map are dated snapshots and now describe pre-1c state at two lines; left as history.
- Should node_instances controllers (REST + worker_api) and the MCP twin system_fleet_tool.rb#update_instance permit `config` WHOLESALE at all? IMP-96f542e82141 changed detection only; the lint now names all three writers. Ruling: allow-list config keys (recommended) or accept wholesale writes.
- Transport refusal SHAPE diverges for a de-advertised action: ActionCable raises a JSON-RPC ToolNotFoundError, streamable HTTP now returns a success:false result envelope (fc6d465f5). Ruling: pick one (recommend the result envelope on both, since agents retry on -32xxx errors).
- SDK guard scope (35b7ab3e): the credential-POST guard is on the provider MINT, not on the credential — a credential POST naming a type that already has a Provider row succeeds even when that type's SDK gem is absent. Confirm, or extend the refusal to the credential attach.
- Behaviour change: provider_credentials create/test now 403 (permission before_action) where they previously 400'd on a missing provider_id for unauthorized callers.
- Promotion dwell (49e9491e): ONE stale-heartbeat instance among N now makes the version ineligible (strict by driver decision); the liveness threshold is deliberately not operator-tunable; the operator REST promote and MCP system_promote_module_version still bypass PromotionCriteria entirely (pre-existing). Confirm the strictness, and whether the manual promote paths should consult the criteria (recommend: yes, as a warning not a refusal).
- schema.rb is hand-patched on this maintainer checkout because the post-migrate auto-dump is force-disabled and a core-mode dump would include private-extension tables; verify with the public-bundle worktree before release.
- schema.rb: a core-mode db:schema:dump on this checkout also rewrites one unrelated line (ai_approval_requests check_execution_status constraint, PG ARRAY rendering drift). Left alone; expect it to show up on the next honest dump.
- NEW PERMISSION `system.fleet.manage` (grant: admin) added by APO-2e for system_update_sensor_config — an authz-catalog addition; the role-grant reconciler lands it on running installs (absence-only). Confirm admin is the right audience (not folded into worker-only system.fleet.autonomy).
- Concierge availability derivation is account-wide while ConciergeToolBridge narrows the model's actual tool list on the tool-capable lane (reviewer follow-up, unfiled — file if you want the prompt to match the model's real tool list exactly).

## Deploy plan (needs your go): nothing from this session is deployed
- All work is on dev-loop/dev-improve (parent + extensions/system), unpushed. Deploying needs: merge/push to the branch the build clones (memory: builds clone CORE from the GitHub mirror — push the mirror first), then a THREE-module platform build (hub-backend, hub-frontend, extension-system) plus a system-base build for the agent (APO-2a changed the heartbeat wire payload), then restart. Migrations pending on deploy: first_seen_running_at, lease_class rename, lifecycle_class default→NULL, sensor_configs (auto-apply on live is the rule; core+extension promote SKEW is the known outage shape — deploy all modules in one batch).
- Behaviour that goes live with it: 14 requires_approval executors park on first call (seed policy rows first); availability_pct has a default 99.5 target so the SLO breach arm becomes live; PromotionCriteria strictness.
- APO-1e prerequisite (from 1b review): Ai::Tools::FederationTool#execute overrides BaseTool#execute without super, bypassing the declaration registry, deny overlay and validate_params!. Must be fixed before the fail-closed flip; file as its own task.
- A federation principal is refused at PARK time by the deferred replay seam (core holds no handle on the partner row) — federation-initiated gated calls cannot be deferred. Acceptable while federation has zero live peers; revisit with the federation campaign.
- DEPLOY GATE (APO-3b): `rails db:seed` must be re-run after deploy — the Ai::Skill system_prompt for platform_resilience is seed-written and the live text still describes the old drain markers; seeds never re-run on an existing install.
- Scale-OUT via platform_resilience is clamped (max delta SiteSetting, default 5) and runs on system.instances.create but has NO approval category (matches the platform_deploy precedent). Ruling: keep (additive) or add system.platform.scale_out auto_apply_within_bounds once APO-3a lands.
- RED SPEC ON THE BRANCH (filed): autonomy_domain_pivot_spec — 13 registered categories lack DOMAIN_PREFIXES after the APO-1c registrations. Will be fixed first in batch 4; do not merge before.
- Instance-pool gated create/destroy in the frontend still render the 202 as a failure (only update was fixed); folded into the MCP-twins follow-up.
- DEPLOY GATE (APO-3a): the system_provisioning mission TEMPLATE row on a live install will not carry auto_scale_min/max_replicas until re-seeded (seeds never re-run) — same db:seed re-run as APO-3b. policy_declarations.rb:926 still advertises the single-key auto_apply_window pointer (cosmetic, reviewer-deferred).
- PAGINATION (APO-8b) confirmations owed: 37 list actions now return one page by default — ai_tools_list_default_limit (fallback 100) clamped by ai_tools_list_max_limit (fallback 500), neither SiteSetting seeded; eight actions that used to return EVERY row now page; ordering changed on nine actions (one sort key + id tiebreak; list_instance_types_by_gpu now walks by id); system_sdwan_list_ovn_acls disagrees with the OVN compiler at equal priority (compiler ties on name). Four get_* verbs still hand-roll truncation (queued residue).

## Branch health (must be green before merge) — specs reported red on dev-loop/dev-improve by finalizers
- spec/controllers/api/v1/system/autonomy_domain_pivot_spec.rb:84 — 13 categories without DOMAIN_PREFIXES (filed IMP-4ba48fd088ce, runs first in batch 4)
- spec/docs/fleet_sensors_signal_kinds_spec.rb:381 — SiteSetting token `system.project_metrics.sample_freshness_seconds` in FLEET_SENSORS.md:346 trips the dotted-token heuristic (from APO-2a docs)
- spec/services/system/autonomy/action_category_router_spec.rb:71 — BaseSkillExecutor calls gate_action! while undeclared in ROUTERS (from APO-1c)
- spec/docs/node_lifecycle_class_docs_accuracy_spec.rb:366 — seed-writer equality enumeration vs smoke_test_instance_replace.rb (from APO-4; re-verify on HEAD)
- spec/requests/api/v1/mcp/system_ingress_tool_spec.rb 'approval gating' ×4 — reported red on a working tree mid-batch; re-verify on HEAD
- docs/SKILL_EXECUTOR_CATALOG.md stale by 3 executors (regenerate: rails system:skills:generate_catalog)
Driver will run these files after batch 3 completes and fix or queue each.
