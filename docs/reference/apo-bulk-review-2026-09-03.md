# APO bulk review — batch 4 (2026-09-03)

Addendum to [apo-bulk-review-2026-09-02.md](apo-bulk-review-2026-09-02.md). Batches 1–3 rulings were
approved on 2026-09-02 ("Approve all rulings"); this document covers batch 4 (26 tasks) and the deploy.
Everything is on `dev-loop/dev-improve` in both the parent repo and `extensions/system`, **unpushed**.

## 1. Rulings (decided 2026-09-03 02:48 by the operator)

R1 passed (IMP-0ddfd8a60032 disposed). R2 approved → IMP-57a4b1ef94b3. R3 kept. R4 approved → IMP-7e84ae0ccc91. R5 approved → IMP-4d6423bf4eb3. R6: leave ceilings unset. R7 accepted. R8: set `module_promotion_required_count` after deploy. R9: drive the 4 critical CVE exposures after deploy. Extra: pre-existing PUT 500 → IMP-f9a184e832ac. Deploy: **approved when branch health is green** (push + one batch + migrations + seed + post-checks).


| # | Item | Recommendation |
|---|------|----------------|
| R1 | IMP-0ddfd8a60032 provider SDK guard at the REST + credential-validation doors — committed and green (133 ex), guardrail-parked only because `credential_validation_service.rb` matches `**/*credential*`. The change ADDS a refusal; no credential material is handled. | Dispose blocked → passed |
| R2 | Offer `01a063db-c869-7117-b7f6-f88b7061ab4a`: bounded one-shot collection of the 4 inert operator instance-pool policy rows on already-booted installs (ops-hub included), restricted to rows still at the seeded verb. | Approve, batch 5 |
| R3 | IMP-51e5c6184ae4 migration `20260902210000` deletes the 3 underscored architecture policy rows on running installs and WARNS per account when the surviving dotted row is looser than require_approval (it was inert before; the release opens that gate). | Keep the delete + warning; read the migration log on ops-hub after deploy |
| R4 | tools/list on streamable HTTP now carries a 1 KB result-envelope schema per platform tool: body 392 KB → 1034 KB in ONE page (TOOLS_PAGE_SIZE 1000). | Keep the envelope; ~~file a shrink follow-up (hoist behind `$defs`/`$ref`) for batch 5~~ **CLOSED 2026-09-03 by IMP-7e84ae0ccc91** — the `$defs`/`$ref` hoist is NOT implementable on the MCP wire: each entry's `outputSchema` is a standalone document the client compiles the moment tools/list returns (@modelcontextprotocol/sdk 1.29.0 `client/index.js` `Client#cacheToolMetadata` -> `ajv.compile`, no rescue), and MCP defines no cross-entry definitions store, so an unresolvable `$ref` drops the WHOLE catalog for that client. The wire is already shrunk by `Rack::Deflater` when gzip is negotiated (~10x), but the body a client PARSES was unchanged at ~1.1 MB. **AMENDED RULING 2026-09-03 06:52 UTC** (same task): "drop descriptions and provide a mechanism to retrieve tool details on-demand" — a THIRD lever this row's "only two remaining levers" enumeration missed. `Mcp::ToolCatalog` is now the one builder for tools/list entries and cuts every listed `description` to its first sentence (`LIST_DESCRIPTION_LIMIT` 160 chars, word-boundary ellipsis); the long-form gating/envelope/side-effect text moved behind the new `platform.describe_tool`, which returns the full entry from the SAME builder. Measured over ONE session on ONE checkout, real registry, user principal, one page of 625 entries: BEFORE (long-form descriptions) raw 1,109,260 B of which descriptions 120,227 B — 248 over 160 chars, longest 1,477 — gzip 110,483 B; AFTER raw 1,037,808 B of which descriptions 48,941 B (longest exactly 160), gzip 84,143 B (12.33x). The `outputSchema` envelope is identical either way at 672,209 B and `TOOLS_PAGE_SIZE` is unchanged, so neither forbidden lever was used. Earlier runs of the same measurement recorded 1,106,704 B / 110,010 B, 1,106,376 B / 109,888 B and 1,105,655 B / 109,653 B, all at 624 entries: the raw body tracks the extension checkout's description text, which moved between runs, which is why both halves of the pair above come from one checkout. No operator decision outstanding on R4. |
| R5 | `Mcp::Principal::DESTRUCTIVE_TOOL_PATTERNS` does not name `system_replace_instance`. Reap-through-replace is refused for instance principals in the gate context; replace alone only acquires a spare. | Add `*replace_instance*` to the deny overlay anyway (one-liner, batch 5) |
| R6 | Platform-wide utilization ceiling: `Ai::Mission#utilization_targets` ships DECLARED-ONLY (constants nil) because a defaulted 85 % ceiling would have opened unattended scale-out for every project inheriting the seeded template's scaling window. | Do NOT set `ai.provisioning.max_cpu_pct` on ops-hub until scale-out is reviewed end to end on a real mission |
| R7 | `System::NodeInstance::WRITABLE_CONFIG_KEYS` (13 declaration keys) is a judgement; any internal caller PUTting another key now gets 422 (none found in worker/core/other extensions). | Accept; review the list once |
| R8 | Override-event noise: `system.module_promotion_criteria_override` fires on EVERY manual blessing while `REQUIRED_COUNT` defaults to 3 on a 1–2 instance fleet. | Set `module_promotion_required_count` on ops-hub after deploy, or accept one event per blessing |
| R9 | 4 critical CVE exposures are OPEN on ops-hub (qemu-guest-agent ×2, nginx, qemu-guest-agent-vm104-devpin); the CVE lane has not remediated them (565 open, 0 remediating). | Operator decision: drive `cve_remediation_orchestration` for the 4, or accept |

## 2. What landed in batch 4 (26 tasks; 25 passed, 1 guardrail-parked)

Campaign `01a0609d` (Autonomous Project Operations): increments 17–23 recorded.

| Task | Area | Result |
|------|------|--------|
| APO-3c IMP-8340af6aede5 | Load balancing (Traefik) | Backend set table + writer emits all active backends, opt-in health checks. Producer door filed as APO-3d IMP-0c10b9fd5596 |
| APO-3b IMP-f4fe1ed1ec1e | Drain verb / Scaling panel | Drain actuates (stop + cordon), pending envelope preserved; PATCH reconciles on every requested target; UI warns on refused/clamped |
| APO-2c IMP-fe1af785f0be | Cost sampler | `cost_usd_mtd` from the pricing catalog over accruing replicas; full-coverage-or-unavailable; project_cost_breach can fire |
| APO-2d IMP-25949cfd28fd | Notify lanes | `autonomy.notified` + `skill.execute_*` durable FleetEvents; error-text redaction filed as IMP-675ed7763230 |
| APO-2f IMP-7684d3f8658a | SLO ceilings | cpu/memory read by ProjectSloSensor against declared-only ceilings; per-metric sampler containment |
| APO-4b IMP-4e49eb79c5e0 | DR replace/reap MCP verbs | Liveness precondition at the door; reap refused for instance principals; replacement hub keeps a hostname endpoint |
| APO-6 IMP-93b83b5c82d8 | DR-3 promote replica | PromoteReplicaExecutor behind split-brain + data-loss gates; WAIVER-ONLY until the lag sampler (APO-6b IMP-5b38cd356010) |
| IMP-067f39468350 | Pool MCP twins | create/update gated like REST; first DeferredToolCall consumers; replay baseline + row lock |
| IMP-1635cb7fa768 | **Security** | admin.access could confer super_admin; invitations had NO conferral guard. Both closed at the predicate |
| IMP-149b35e5f16f | FederationTool | Routed through BaseTool#execute; anti-relay refusal hoisted; APO-1e unblocked |
| IMP-8e3bd13d0136 | Refusal parity | ActionCable transport never held a platform manifest (throwaway registry); parity keyed on tool name |
| IMP-b92421fb7c59 / fb5085178b09 / 369a059ad631 | MCP schema surfaces | outputSchema envelope; catalog enum/items; doc-fidelity value checks |
| IMP-51e5c6184ae4 | Architecture category spelling | One spelling; data migration retires the underscored rows (R3); package_module pair filed IMP-2effedffc990 |
| IMP-5a2b801f3386 | Inert operator pool rows | Operator set sliced to the 4 gated verbs; reconciler pinned (R2) |
| IMP-0ddfd8a60032 | Provider SDK guard | REST CRUD + credential validation refuse an inoperable type (R1); refactor IMP-4c825848bb79 |
| IMP-f28b393916f3 | Module drift disclosure | reporting/silent partition (a blocker: widening alone would have dispatched sync_modules to agent-less nodes) |
| IMP-842b56d3a5d4 | Parked steps | UI renders parked/executing/rollback_failed; */15 reaper cron on the janitor seam |
| IMP-fd500f2bf5f6 | Delegations | Stored permission-set editor (permission-gated) |
| IMP-d6826c872d88 | Manual promote | Consults PromotionCriteria and WARNS (D17); panel half filed IMP-bdb650b82c65 |
| IMP-1b65222b8d5f | NodeInstance config | Allow-listed keys on all 3 writers (R7) |
| IMP-68403ec0358d | Pool attribution | `system.pool.claimed/released` ledger with a claim id |
| IMP-6a112bebbe9f | Test harness | Factory role scoped to the account (private-bundle sweeps ran green) |
| IMP-fdb2ee10ba37 | Package search | Declared sort orders honoured; sort enum declared |
| IMP-2f1c8c089113 | CVE audit | No defect on HEAD; prod: 565 open / 0 parked (R9) |
| IMP-cb2da06a384b | Drain vs replenish prose | (see §4 status) |

Follow-ups filed and approved during the batch: IMP-0c10b9fd5596, IMP-5b38cd356010, IMP-2effedffc990, IMP-4c825848bb79, IMP-675ed7763230, IMP-bdb650b82c65.

## 3. Deploy (approved 2026-09-03 02:48; COMPLETE 04:24)

Core `develop` = `0535932ed` (merge of `dev-loop/dev-improve`, 145 commits, resolving three conflicts against develop's dev-loop-tooling commits; merge-sensitive specs 80/0) pushed to Gitea and GitHub at 03:50. Batch A `01a06558-9869-7c43-8d03-a63333932edc` builds extension-system (unchanged ext tip), hub-backend, hub-frontend, hub-worker serially. **The extension `develop` push is deliberately held**: `PlatformPushController` auto-dispatches a native batch on a push to `powernode-system` develop, which would build the extension AND fan out to system-base + the whole module catalog before core is live (the 2026-08-28 skew outage shape). Sequence below is the plan of record.

1. Push `dev-loop/dev-improve` (parent + `extensions/system`) — the build clones core from the GitHub mirror, so the mirror goes first.
2. One batch: the THREE platform modules (hub-backend, hub-frontend, extension-system) plus system-base (APO-2a changed the agent heartbeat wire payload). Never let the extension promote alone (core+extension skew is the known outage shape).
3. Migrations that auto-apply on live: `20260902120000` module_first_seen_running_at, `20260902133000` lease_class rename, `20260902160000` lifecycle_class default→NULL, `20260902180000` sensor_configs, `20260902200000` sdwan_service_backends, `20260902210000` retire underscored architecture policies (data; read its WARNING lines).
4. `rails db:seed` re-run (seeds never re-run on an existing install): platform_resilience skill prompt, system_provisioning template scaling bounds, `system.replica_promote` and the 14 gated-executor policy rows, the third skills seed (DR).
5. Post-deploy checks: `/up` 502 window ~3 min; MCP connector reconnect; role-conferral fix live (IMP-1635cb7fa768 is the URGENT item — ops-hub is exposed today); pricing catalog populated before expecting any cost breach; R8 setting.


**Outcome (04:24):** ops-hub runs core `44a1a0617` (hub-backend v88, hub-frontend v27, hub-worker v27) and extension `f14219df` (v79), verified by content on the node; all seven migrations applied (the architecture-policy retirement found 0 underscored rows and 4 dotted rows to keep); `db:seed` re-run by hand (rails-start seeds on first boot only) — Platform Resilience / Promote Replica skills refreshed, `system.replica_promote` and `system.platform.scale_out` policy rows present, template scaling bounds present; R8 `module_promotion_required_count` = 1. Two traps hit and recorded in memory: the core-range extension build clones the extension's `develop` tip (v78 was byte-identical to the 08-28 artifact), and a push to extension `develop` auto-dispatches a fan-out batch — parked via `system.module_builds.trigger_ref = refs/heads/deploy-hold-2026-09-03`, which stays parked until the agent/system-base rebuild is wanted. Breakglass armed 04:13–04:24 and revoked (verified on VM 600). Still owed: R9 (drive the 4 critical CVE exposures).

## 4. Branch health (03:40)

Pattern validation 52/52; catalog and schema fresh; 19-file guard set on a driver lane DB: 1600 examples, 3 failures — all introduced by batch-5 commits after batch 4 closed and fixed by the driver (FLEET_SENSORS.md policy count 56→55 after the package_module cleanup, `system.replica_promote` missing a DOMAIN_PREFIXES entry) or in-flight in an uncommitted lane tree (`system_set_service_backends[backends]` prose-only value set, owned by APO-3d's lane). Stray diagnostic spec gone; working trees clean apart from the submodule pointer.

**Sprint state**: batches 5 (12 tasks) and 6 (13 tasks) run on seven per-lane test databases with Fable implementers; 7 of 25 closed at 03:50. Batch 7 (8 fleet-tool/policy tasks) staged behind extB.

## 5. Batch 5 plan (draft)

- extA: IMP-0c10b9fd5596 (APO-3d backend-set producer) → IMP-5b38cd356010 (APO-6b lag sampler + stop_command) → IMP-bdb650b82c65 (promote panel half)
- extB (policy_declarations chain, then fleet tool): IMP-2effedffc990 → IMP-f986d379120a (scale_out policy) → IMP-e025722ef14e (APO-5 remainder) → IMP-4c825848bb79 (will guardrail-park)
- extC: IMP-675ed7763230 (audit error-text scrub) → IMP-57a4b1ef94b3 (R2 collection, data migration: solo slot) → IMP-f9a184e832ac (PUT 400)
- core: IMP-4d6423bf4eb3 (R5 deny overlay) → IMP-7e84ae0ccc91 (R4 tools/list shrink)
- Solo/migration (after the deploy window): IMP-f2a7a729d39b (lifecycle step 2)
- Held until deploy + telemetry window: IMP-31e7c3dbeb2a (APO-1e fail-closed)
- Held (operator): IMP-4c0a826ad21a, IMP-b54e49ddfc40, IMP-01b1e152f667 (business extension), IMP-222dd9bce564 (permissions path); blocked IMP-74995230ed5b
