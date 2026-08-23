# Autonomous Infrastructure on Demand — What's Missing, and What Isn't

**Question** (operator, 2026-08-12): what tools does the platform lack, and what processes
need defining, for fully autonomous infrastructure on demand — ad-hoc app development and
deployment, service deployment and configuration, proactive agentic monitoring, and live
remediation?

**Method**: every load-bearing claim below names a mechanism (symbol, table, seam, or
absent applier) and was verified in source or established empirically this cycle —
including the evolution-loop campaign's INC-1 failure, which is treated here as data.
Prior ground truth reused: the 2026-07-28 hand-executed provisioning loop (six gaps, three
since closed), the 2026-07-02 self-improvement evaluation, and the dryrun campaign's
zero-intervention E2E pass.

**The short version**: the platform already owns almost every *verb* it needs. What is
missing is concentrated in three places — it cannot yet **act on what a deployed system
tells it** (the adaptation lane dead-ends), it cannot **see more than drift** (telemetry
has storage, sensors, and adapters but no producers), and it cannot **author what it
deploys** (agents build and assign modules but cannot create one). Most of the remainder
is process, not code.

> **Correction (2026-08-21, IMP-a67be4fe9041):** "cannot create one" was already stale at
> ratification — see the correction under §3's authoring-seam bullet. Agents have been
> able to author a buildable module's manifest over MCP since 2026-08-06 (`f65e72c7`); the
> create arm's residual is the `modules/<slug>/` build payload. The three-arm framing and
> every other claim in this paragraph stand.

---

## 1. Ad-hoc application development + deployment

**Exists — more than expected:**
- The full intent→infrastructure path is proven hands-off: concierge NL → brief →
  deterministic plan synthesis → provision → verify → teardown (run `20260809g`).
- **"Run my code" exists end-to-end**: a brief carrying `repo_url` gets a
  `deploy_app_code` step appended (`PlanComposerService:185,:1438`), executed by
  `System::Ai::Skills::DeployAppCodeExecutor` (SSH + systemd onto the provisioned
  instance, start-command inference, private-repo deploy keys), with a lifecycle ledger
  (`Ai::ProvisioningCodeDeployment`: pending→cloning→installing→starting→running,
  `commit_sha`, `public_url`) and a real rollback (`rollback_deploy_app_code` stops and
  disables the unit, marks `rolled_back`).
- Code iteration machinery: RalphLoop / dev-improve / campaigns — proven on the
  platform's own code (0% revert across 166 improvements in the 30-day evaluation
  window), and already repo-portable (`ImprovementRecommendation`'s polymorphic
  `Devops::GitRepository` target).
- Repo + CI plumbing: `create_gitea_repository`, `dispatch_to_runner`,
  `lease_ci_runner` / `provision_ci_worker`; the full `docker_*` deploy surface
  (services, stacks, rollback) and K3s.

**Genuinely missing:**
- **Deployed app code is unobserved after `running`.** No fleet sensor reads
  `ProvisioningCodeDeployment` health, and `System::Fleet::Sensors/` contains **no**
  container-runtime, docker-service, or app-health sensor at all (verified: the sensors
  directory has none). An app deploy succeeds once and is never looked at again —
  `docker_restart_container` / `docker_rollback_service` exist as verbs with no
  sensor→applier lane behind them.
- **No Application aggregate.** Repo, build artifact, deployment row, docker
  service/stack, exposed `Sdwan::Service`, and SLO targets are disconnected fragments —
  nothing records "service S is app A at version V," which is what remediation and
  rollback would need to target. (The nearest join is `ProvisioningCodeDeployment` +
  mission configuration, which covers only the SSH+systemd path.)
- **No app-development loop shape.** dev-improve drains *approved improvement offers*
  against indexed repos; there is no defined loop for "develop app X in repo Y to
  acceptance criteria Z" driven from a mission. The tools (loop, repo scoping, CI
  leasing) exist; the loop *shape* — brief → scaffold → red-first tests → iterate →
  review gate → deploy — is undefined.
- **Build throughput is one shared queue** (empirical: 10+ minute module-build waits,
  2026-07-28). Autonomous development multiplies build demand; this bottleneck arrives
  before most others.

**Processes to define:**
- The review gate for AI-written *app* code: the platform's own code has
  `/code-review` + the verification gate + operator approval; app code has nothing
  declared. Who (or what) reviews, what evidence ships a version, who owns rollback.
- App/repo sprawl control — the module-authoring R1/R2/R3 reuse gate, applied to "should
  this be a new app/repo at all."
- Promotion: `ProvisioningCodeDeployment` has states but no staging→live notion; define
  what promotes and what the previous-version rollback contract is.

---

## 2. Service deployment + configuration

**Exists — this is the platform's strongest domain:**
- Module-as-service delivery: manifest `services:` → generated systemd units, versioning,
  **canary → promote → rollback** (`module_mark_canary`, `promote_module_version`,
  `rollback_module_version`) with a real staging→blessed applier
  (`apply_module_promotion`), rolling upgrades with a circuit breaker, and **live
  recomposition** (hot reconcile onto the running root, deletion gap closed `a3b94cdf`).
- Build batches are now cancellable (`system_cancel_module_build_batch` + `cancelled_at`,
  deployed 2026-08-10) — the unstoppable-batch incident's kill switch exists.
- Exposure: local (`Sdwan::Service` `/svc/<slug>` + ForwardAuth) and public (VIP → port
  map → ACME → Traefik), `service_discovery_compose`, `reverse_proxy_compose`.
- Declarative topology: GitOps (register/sync/drift-report/apply, auto-apply repos).
- Config: DB-driven (`SiteSetting` / `Account#settings`) with a **wired** drift lane
  (`system.config_drift` → `apply_config`).

**Genuinely missing:**
- **The authoring seam** (2026-07-28 gap 2; offer `019fc9f3` pending): agents can build,
  assign, and compose *existing* modules but cannot **create** one — authoring is a human
  editing `manifest.yaml` + a `stage15.sh` case-arm in git. Every "deploy a NEW service"
  flow dead-ends here.

  > **Correction (2026-08-21, IMP-a67be4fe9041):** the bullet above was already stale on
  > the day this document was ratified. Manifest authoring over MCP had landed **six days
  > earlier, on 2026-08-06, in `f65e72c7`** (`extensions/system`): `system_create_module`
  > and `system_update_module` accept `manifest_yaml` and route it through
  > `System::ManifestImportService`, which is exactly what makes a module visible to
  > `System::ModuleBuildPlannerService` (its buildable set is "has a non-blank
  > `manifest_yaml`"). An agent therefore **can** create a module and have it planned for
  > build; "cannot create one" is wrong. The residual is narrower than "authoring":
  >
  > 1. **The build payload — still human-only through git.** A module that ships or builds
  >    files needs a `modules/<slug>/` tree and a `case "$MODULE"` arm in
  >    `extensions/system/scripts/module-build/stage15.sh`. Both are committed by a human;
  >    no MCP surface authors either. This half of the 2026-07-28 gap-2 claim stands.
  > 2. **The R1/R2/R3 sprawl gate — was advisory only.** It lived as prose in the
  >    `system_create_module` tool description ("run system_discover_modules before
  >    authoring") and in `extensions/system/docs/runbooks/module-authoring.md` Phase 0,
  >    both addressed to a human reader and enforced by nothing in `create_module`.
  >    **Closed on the MCP authoring surface, 2026-08-21** (IMP-a67be4fe9041): a manifest
  >    that would add a new name to the planner's buildable set is now refused unless the
  >    caller declares a `reuse_check`, and the existing modules that declaration claims to
  >    have considered are verified to exist. Scope is exactly that surface — the REST
  >    `import_manifest` endpoint, the CI publish path, and `rails db:seed` still call
  >    `System::ManifestImportService` directly and are deliberately ungated, because they
  >    are the human/committed paths this gate exists to keep agents honest about.
  >
  > No conclusion of this document is changed by this correction. The create arm is still
  > the third of the three arms in §5 and is still unfinished — its residual is the build
  > payload, not the manifest.
- **The `verify:` manifest probe block** (2026-07-28 gap 4 — design settled, unbuilt):
  no callable "node N now provides capability C" primitive. The settled spec matters as
  much as the feature: `command` probes must assert `resolves_to` (a resolved path, not
  existence), and must run in login AND non-login shells — the VM-9000 shadowing bug
  passed an existence probe in one shell while broken in the other.

**Processes to define:**
- SLO ownership: `slo_targets` exist on missions and per-module score evaluation exists
  (`Slo::ScoreEvaluator`), but nobody owns declaring targets per service, or reviewing
  them. Define the owner, the default, and the cadence.
- Canary policy: the promotion machinery exists; the thresholds (what a canary must
  demonstrate, for how long, measured by which oracle) are undeclared.

---

## 3. Proactive agentic monitoring

**Exists — a complete nervous system missing its sense organs:**
- 24 fleet sensors + 2 CVE sensors + capability-gap sensing (now fully bound through the
  gate, closed 2026-08-04), on a 60s reconcile tick; per-signal fingerprint dedup;
  severity scaling; correlation ids.
- Storage and query for metrics **already built**: `System::ProjectMetric` written every
  tick by `ProjectMetricsCollector`, read by `ProjectSloSensor`; the
  `Slo::TelemetryAdapter` FleetEvent convention (`metric.latency_ms`) is the designed
  transport.
- Failure forensics: `recent_signals`, `inspect_correlation`, `attribute_failure`.
- Outcome accounting: `RemediationOutcome` validate arc, ineffective-streak escalation
  (F3-11), consent budgets, trust scores + emergency demotion, `send_proactive_notification`.

**Genuinely missing:**
- **Telemetry producers.** `sample_metric` has exactly two live branches
  (`replica_count`, `region_count`); latency, availability, cpu, memory, and cost are
  all honest `unavailable`, and the FleetEvent metric convention has **zero writers**.
  The intended sources are already named in code comments (agent heartbeat for cpu/mem,
  SDWAN edge probes for latency/availability, billing MTD for cost). Consequence:
  proactive monitoring can currently see *drift* but not *health, performance, or
  spend* — two of the three `ProjectSloSensor` signal kinds are unfireable outside
  specs.
- **Post-compose/post-deploy verification reporting**: the `verify:` probe results in
  the heartbeat + a `ModuleVerifyFailedSensor` (same settled design as §2).
- Infra cost aggregation in core (the LLM ledger exists — `BudgetTransaction`; per-node
  infra spend does not).

**Processes to define:**
- **Oracle discipline as policy**, not habit: every oracle names its production entry
  point and preconditions; a zero read with a precondition unmet is "not measured,"
  never "pass"; counters over row-existence; ground truth over self-report. (Three
  instruments this cycle validated configurations production never uses; the routing
  oracle silently reads zero unless a default-OFF flag is on.)
- Alert routing: severity → gate species → who is paged, and when. The notification
  verb exists; the paging policy does not.

---

## 4. Live remediation

**Exists — for infrastructure-shaped problems, this works today:**
- **Four fully wired drift lanes** (module, config, template-closure, storage-assignment:
  sensor → binding → policy gate → applier → outcome scoring), plus instance self-heal
  (silent-instance reboot with AASM-legal action selection, provider-state convergence),
  honeypot quarantine, CVE remediation orchestration, SDWAN peer remediate / key rotate /
  VIP failover, boot-image drift rollout, GitOps apply.
- Graduated authority: InterventionPolicy (auto / notify / require-approval / block),
  per-module consent budgets, forced escalation after proven-ineffective streaks, kill
  switch on every write path.
- **The control plane already protects itself**: `foreign_control_plane_skip` and
  `self_managed_skip` (RCP v2 INV-1) make remediation refuse targets it must not touch.
- Storage migration as a workflow-gated lifecycle (plan → approve → sync → cutover →
  revert).

**Genuinely missing:**
- **The adaptation lane** — remediation of a *deployed system's shape* (scale, placement,
  topology) rather than its configuration. This is the evolution-loop campaign, its five
  approved tasks, and its hardest empirical lesson: INC-1 (the applier alone) was
  **unbuildable in isolation** — a propose-only lane with no consumer has no reachable
  correct state (false stuck-escalations → unbounded churn → permanent silence, across
  three review passes). The lane must land consumer-first or whole.
- Scale-down actuation (`ScaleProjectExecutor::STRATEGIES` has no removal), and the
  composition defects already on the approved backlog (non-convergent drift arithmetic,
  executor-contract mismatch, compute-only scale-out).
- Service/app-level remediation lanes (§1): the verbs exist, no sensor feeds them.

**Processes to define:**
- The **convergence contract**: a remediation is *effective* only when the originating
  signal's ground-truth metric clears — never when the actuator returns success. The
  wired lanes get this from `RemediationOutcome`; adaptation needs the fingerprint-clear
  seam; app/service lanes will need the same from day one.
- The graduation ladder as a standard: report-first → operator-approved → auto within
  declared bounds — per lane, with the bound always config-resolved, and destructive
  actions (removals) never auto-applied at any rung (ratified precedent).

---

## 5. The critical path — if only three things get built

1. **Close the adaptation lane, consumer-first, as one increment** (the act arm).
   Applier + fleet-chain gate + runner dispatch + post-adapt verification +
   fingerprint-clear outcome + `remove_replicas` — the five approved tasks, resequenced
   under the producer/consumer law rather than drained as independent slices. Four wired
   lanes prove the shape; this is the only lane that adapts a *running* system, and every
   "monitor, adjust, improve the deployed topology" ambition actuates through it.
2. **Telemetry producers + the `verify:` probe primitive** (the sense arm). Storage,
   sensors, and adapters exist; wire heartbeat cpu/mem and one latency/availability
   source into `System::ProjectMetric`, and build the settled probe spec. Highest
   leverage-to-effort ratio on the platform: it turns monitoring from drift-only into
   health/performance/cost, gives every deploy a self-proof, and is the precondition for
   any SLO-driven behavior.
3. **The agent authoring seam** (the create arm). A declarative module-authoring path
   (manifest + file-spec committed through Gitea, R1/R2/R3 sprawl gate enforced *by* the
   automation, batch-cancel already in place) so that ad-hoc development can produce a
   deployable unit without a human editing two files in git.

   > **Correction (2026-08-21, IMP-a67be4fe9041):** part of what this arm asks for already
   > exists. **Before building from this arm, read the correction under §3's
   > authoring-seam bullet** — an agent has been able to author a buildable module's
   > *manifest* over MCP since 2026-08-06 (`f65e72c7`), and the R1/R2/R3 gate was made
   > mechanical on that same surface on 2026-08-21. Note the difference from the clause
   > above: that path writes `manifest_yaml` to the **database**, not a manifest committed
   > **through Gitea**, and it does not author the `modules/<slug>/` file-spec payload or
   > its `stage15.sh` build arm. Those remain the residual. The arm itself is unchanged —
   > still unfinished, still the create arm.

These are respectively the act, sense, and create arms; everything else in this document
(the app aggregate, unified approval queue, build throughput) amplifies autonomy but does
not enable it.

---

## 6. Structural, not merely unbuilt

Shapes the platform keeps re-deriving badly. A rule that prevents recurrence is worth
more than another component:

1. **The producer/consumer increment law** (empirical, INC-1): a lane split is a valid
   increment boundary only if one half is independently exercisable — and that half
   lands first. Adopt at planning time: every increment names its consumer.
2. **Deterministic-first did not generalize** because it lived as prose. The provisioning
   composer learned "recognized scenario → synthesize, LLM only for novel" the hard way;
   the adaptation composer regressed to LLM-first anyway. Rule: every intent→plan seam
   declares a recognized-scenario predicate and stamps composer provenance — and the
   lesson gets a guard (a scan or review checklist item), because this platform's own
   self-improvement evaluation already proved that un-guarded lessons recur
   instance-by-instance forever.
3. **Oracle discipline** (three failures this cycle): instruments drift away from the
   production path — specs stubbing the interesting seam, fixes reading legacy test
   seams, assertions passing because they no longer reach what they name. Codify: every
   oracle/spec names the production entry point it exercises; "not measured ≠ pass";
   counters over rows; ground truth over self-report.
4. **The approval species rule is unenforced.** Four mechanisms in two species (policy
   gates: may this *class* of action run; workflow gates: checkpoint inside *one*
   operation) with no shared queue or UX. Minimal fix: a gate registry with declared
   species and one operator queue view. Every future autonomous lane will otherwise mint
   mechanism number five.
5. **Learning feed-forward is the compounding bottleneck**: learnings are write-mostly
   (avg effectiveness 0.047 at last measure), and recurring defect classes get drained
   one instance at a time. The rule already proposed and still right: a class that
   recurs gets a *guard*, not another fix.

---

## 7. Where full autonomy must NOT go

A credible autonomy design names its own limits. These stay operator-gated at every
tier, including `autonomous`:

- **Key material and credentials** — never generated, output, logged, or rotated by
  agents (Vault-only; operator UI). Absolute, already policy.
- **The irreversible-external class** — DNS repoints, federation trust acceptance,
  payment/billing mutations, terminating anything outside a run's declared blast-radius
  prefix. The decision-authority spectrum already parks these even at its top tier;
  keep it that way.
- **The control plane itself.** The platform must never autonomously remediate its own
  hosting stack — the CVE-storm self-detach outage is the standing precedent (a
  self-hosted control plane that damages itself cannot recover itself). The
  `foreign_control_plane_skip` / `self_managed_skip` rails exist; treat them as
  load-bearing invariants, extend them to every new lane, and test them adversarially.
- **Module publish/promote** stays gated even with batch-cancel built: publish
  auto-promotes and fan-out has planned 21+ modules from one edit.
- **Destructive removals never auto-apply** (ratified, evolution-loop §4) — scale-in,
  instance termination, volume deletion always take an approval, regardless of bounds.
- **Agents never raise their own autonomy**: no self-promotion of trust tiers, and no
  baseline mutating its own skills (account-level shared config escapes any per-run
  blast radius) without a dedicated, operator-signed containment design.
- **Business-policy values** — budgets, pricing, ceilings — are configuration the
  operator sets; agents consume them and may never write them.

---

*If one sentence is all the operator reads*: the platform already owns nearly every verb
full autonomy needs — what it lacks is the act arm (an adaptation lane that must be built
consumer-first), the sense arm (telemetry producers for storage that already exists), and
the create arm (an authoring seam for modules and apps); build those three, hold the
lines in §7, and the rest is process definition, not new machinery.

*(2026-08-21, IMP-a67be4fe9041 — this sentence stands as written; the create arm's scope
is narrower than §3 originally stated. See the correction there.)*
