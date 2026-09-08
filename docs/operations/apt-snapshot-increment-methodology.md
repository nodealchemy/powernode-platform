# Keeping module base packages current: snapshot-increment methodology

Status: research + design, report only (2026-09-08, revised the same day after two operator
clarifications). Nothing here is implemented.
Scope: the `build.apt_snapshot` pin every platform module carries, how a bump of it
propagates today, and a two-lane mechanism (security fast and automatic, features
infrequent and operator-evaluated) that rebuilds only the modules whose resolved package
closure actually changes, with package and CVE evidence in front of the operator before
anything builds.

## Executive summary

- **Operator decisions received (verbatim intent):** stay on noble, no 26.04 migration now;
  "run recent package versions without rebuilding all modules in a long-term/sustainable
  way"; "security updates be highest priority with fast deployment, especially with CVE
  reports, and normal package updates happen at a regular but infrequent basis determined
  by changelog, new features, major vs minor updates, etc, which should be evaluated and
  decided upon independently." Per-module snapshot drift is accepted with a uniform floor.
- **Today:** 31 of 32 manifests pin `20260415T000000Z` (146 days old); the boot image pins a
  different snapshot; every build publishes its resolved package lock as an OCI layer and
  nothing reads it; CVE matching is NVD keyword matching minted as `suspected`; a pin bump
  is a 31-manifest commit that plans the whole catalog and the build-skip cannot help
  because the pin is a hash input (§1).
- **Design:** ingest the lock at publish (§3.1); a candidate evaluator that diffs each lock
  against a newer snapshot's indices, confirms with an unprivileged `apt-get -s` (a
  technique already in the repo), applies a layer-compatibility policy, and attaches
  pocket, changelog and USN/CVE evidence (§3.2); two lanes on top of it (§3.3, §3.4); a
  `snapshot` batch trigger that builds an explicit set without reverse-dependency fan-out
  (§3.5); promotion via the existing batch-atomic holdback with a soak (§3.6).
- **Security lane:** hourly OSV/USN ingest plus an hourly `noble-security` index watch;
  a candidate on every USN or pocket change touching any lock; only the affected modules
  (plus floor and overlap groups) build automatically behind a dedicated approval category;
  CVE/USN ids ride in the batch metadata; target from USN publication to fleet: under one
  hour typical, under two at the tail, for content modules; hub modules add an operator
  release (§3.3).
- **Feature lane:** monthly (first Tuesday 02:00 UTC) or on demand; a changelog-driven
  per-module report (version delta classified by Debian version semantics, pocket,
  changelog excerpt, feature vs bugfix evidence); nothing builds until the operator selects
  modules. A snapshot pin is all-or-nothing per module: no per-package cherry-pick; the
  closest achievable is a per-module `release+security` pocket set or a per-module apt
  preference on a version that still exists at the candidate (§3.4).
- **Lane interaction:** a security fix and feature riders on the same snapshot for one
  module move together; riders are reported and classified, and a rider policy decides
  whether a batch with a major rider still auto-dispatches (§3.4.3).
- Open decisions are in §5.

## 1. The present scheme, verified

### 1.1 Where the pin lives and how it is consumed

| Fact | Evidence |
|---|---|
| Every manifest pins `build.apt_snapshot: "20260415T000000Z"`; `vault` has no pin (live archive) | `grep apt_snapshot modules/*/manifest.yaml`: 31 identical values; `modules/vault/manifest.yaml` 0 hits |
| Stage 1 maps the pin to `https://snapshot.ubuntu.com/ubuntu/<ts>/` and mmdebstraps `noble` `minbase`, `main,universe`, per job | `scripts/module-build/stage1-rootfs.sh:121-127,200-209` |
| mmdebstrap adds `noble-updates` and `noble-security` automatically for a stable suite, so the rootfs does carry security updates up to the pin | mmdebstrap(1): "If SUITE does not refer to 'unstable' or 'testing', then SUITE-updates and SUITE-security mirrors are automatically added"; no explicit pocket appears anywhere in `scripts/` |
| `none` opts a module out to the live archive | `stage1-rootfs.sh:124-126` |
| `log-forwarder-vector` and `storage-tools` add live vendor apt repos (documented irreducible nondeterminism) | `stage1-rootfs.sh:141-151` |
| Resolved set captured from the chroot's dpkg db as `name\tversion\tarch` | `stage1-rootfs.sh:225-228` |
| The boot image has its own, different pin | `initramfs/.gitea/workflows/build.yaml:53` (`20260430T000000Z`) |
| `system.ci_builder.apt_snapshot_override` is an assertion against the manifest, not a mutator; a mismatch refuses the build | `node_api/config_controller.rb:583-597`; `module-forge-build.sh:343-355` |
| Manifest import stores `config.build.apt_snapshot` on the module | `manifest_import_service.rb:42` |
| Builders run at most 2 concurrently by default | `native_module_build_orchestrator.rb:64,1321` (`system.module_builds.max_concurrent_builders`) |

### 1.2 What the build-skip hashes

`compute-build-inputs-hash.sh:116-146` hashes (a) git object ids of declared input paths,
(b) the literal `apt-snapshot:<id>`, (c) `core-ref` for the four needs-parent modules. It
does not hash the resolved package set. So: same pin + same tree = skip (default ON,
`module-forge-build.sh:404-420`); bumping the pin changes every module's hash, so a
fleet-wide bump can never skip even where the closure did not change.
`push.sh:205-215` also annotates `org.powernode.apt-closure-sha256`, computed by
`apt-cache policy` on the runner (`build-platform-modules.yaml:66` is `debian:trixie-slim`;
the native buildenv is a nested trixie tree, `modules/module-forge/manifest.yaml:23`), so it
reflects Debian trixie's candidates, not the noble snapshot, and only top-level names. Its
consumer is default-off (`ci-compute-dirty-closure.sh:405-457`), was left out of the Ruby
planner (`module_build_planner_service.rb:26-31`), and no server code reads it.

### 1.3 What consumes the package list today: nothing

- `push.sh:272` pushes `<module>.packages.txt` as layer
  `application/vnd.powernode.module.packages` with a sha annotation (`push.sh:222,277`).
- `ModuleOciIngestService` selects the erofs layer and ignores the sidecar
  (`module_oci_ingest_service.rb:432-437`).
- The SBOM cache on `ModuleArtifact` (`module_artifact.rb:57-84`) is filled only by
  `POST webhooks/gitea/module_sbom`, which only the external module-repo template posts
  (`templates/module-repo/.gitea/workflows/build.yaml:224`). The native pipeline never does.
- `ExposureCalculator` therefore takes the keyword fallback for every native module and
  mints `suspected` rows that every autonomy lane ignores (`exposure_calculator.rb:14-24,126,163`).
- The CVE feed is NVD only (`feed_ingest_service.rb:21,77`); `affected_packages` come from
  CPE strings (`:18-28`) with no Ubuntu binary package or fixed version.
  `DebVersionComparator` is wired (`version_matcher.rb:16,30`) but has nothing to compare.
- The `cve` batch trigger is a label with no consumer (`module_build_batch.rb:38`).
  "CVE sweep" means `force_all` (`system_fleet_tool.rb:2287`).
- `PackageDriftSensor` covers package-origin modules only and actuates a repository
  metadata sync, not a rebuild (`fleet/sensors/package_drift_sensor.rb:5-27`).

### 1.4 How a pin bump propagates

1. Editing 31 manifests dirties 31 `modules/<slug>/` trees (`module_build_planner_service.rb:130,317`),
   then `expand_reverse_dependencies` (`:335`) closes over `requires`; 14 modules require
   `powernode-system-base`, so the plan is the catalog (21 to 23 modules measured,
   `memory/module-build-fanout-and-kill-switch.md`, `memory/system-repo-build-range-fans-out-to-23-modules.md`).
2. Builds take 3 to 8 minutes each, two at a time, each re-bootstrapping from one upstream
   host (today's partial-backend outage blocked a deploy).
3. Publish auto-promotes per module (`module_publication_processor.rb:105-126`), held for
   members of a multi-module batch until every member lands
   (`module_publications_controller.rb:238-250`, `native_module_build_orchestrator.rb:1069-1128`).
   Partial batches hold everything. Per-module `auto_promote=false` withholds promotion.
4. The `promotion_state` ladder is decorative; `current_version_id` is the only actuator
   (`node_module_version.rb:14,103`; `memory/publish-does-not-promote-walk-the-ladder.md`).

### 1.5 Guarantees vs gaps

| Guarantees | Does not guarantee |
|---|---|
| Identical apt resolution per (module, pin), except vendor repos and `vault` | Any freshness: 146-day-old packages fleet-wide |
| Skip correctness for unchanged tree + pin | Skip on a pin bump whose closure did not change |
| A resolved lock is published with every version | That anyone reads it (no ingest, no SBOM, no CVE mapping) |
| Batch-atomic promotion for multi-module batches | Canary or soak: promotion is fleet-wide when the batch completes |
| Fail-closed drift guard on the pin | A way to bump the pin for a subset without a manifest commit |

## 2. Research

### 2.1 Snapshot semantics

Ubuntu: any timestamp after 2023-03-01, second granularity, `YYYYMMDDTHHMMSSZ`; the
snapshot includes the `-updates` and `-security` pockets; apt on 24.04 supports
`Snapshot:`/`-S` natively ([Ubuntu snapshot service](https://ubuntu.com/server/docs/how-to/software/snapshot-service/),
`apt-get(8)`). Debian documents rounding down to the last import ("you will get the latest
available timestamp which is before the time you specified", imports about every six
hours) and a `Valid-Until` caveat ([snapshot.debian.org](https://snapshot.debian.org/)).
A "snapshot increment" is choosing T2 > T1; there is no published list to pick from.

### 2.2 Answering "would this module change under T2?" without building

1. **Index diff against the lock (cheap, exact for version drift).** Download
   `dists/{noble,noble-updates,noble-security}/{main,universe}/binary-<arch>/Packages.xz`
   from `<snapshot>/<T2>/` once. For every `(name, arch)` in a module's lock the candidate
   at T2 is the highest version across the pockets; compare with `dpkg --compare-versions`
   (`cve_ops/deb_version_comparator.rb`). Reuse: `PackageAdapters::AptAdapter` already
   fetches `InRelease` and parses `Packages.xz`, and normalises `Depends:` to
   `{name, op, version}` (`apt_adapter.rb:6-13,23-46`). An added or renamed dependency is
   always accompanied by a version bump of the depending package, so the module is still
   flagged; the new closure's contents need step 2.
2. **`apt-get -s install` in a private root (exact for the closure).** apt runs unprivileged
   against relocated state (`apt.conf(5)`: `RootDir`/`Dir::*`, "Debug::NoLocking ... can be
   used to run some operations (for instance, apt-get -s install) as a non-root user").
   **Already in the repo:** `derive-file-spec.sh`'s `deb-payload` mode resolves a module's
   `package_spec` with `apt-get install --download-only` against a private
   `Dir::Etc`/`Dir::State`/`Dir::Cache` tree pointed at the manifest's snapshot
   (`scripts/module-build/derive-file-spec.sh:566-583,644-657`). Pointed at T2 with `-s`
   it yields the T2 closure in about a second per module.
3. **Build and compare `packages.txt`** stays the ground truth on the version row, never
   the detector.

### 2.3 Mapping package versions to CVEs and changelogs

- Ubuntu OSV: per-CVE and per-USN records, ecosystem `Ubuntu:24.04:LTS`, `name` = source
  package, `ranges[].fixed` = fixed source version, binaries under
  `ecosystem_specific.binaries`; tarball at `security-metadata.canonical.com/osv/`, files in
  `canonical/ubuntu-security-notices`, updated on change
  ([Ubuntu OSV data](https://documentation.ubuntu.com/security/security-updates/osv/)).
  OVAL and VEX alongside ([Ubuntu OVAL](https://documentation.ubuntu.com/security/security-updates/oval/)).
  Fits `System::Cve.affected_packages` with `ecosystem: "deb"` and the existing
  `VersionMatcher` directly; the `Packages` index's `Source:` field maps lock binaries to
  OSV source names.
- Changelogs: `https://changelogs.ubuntu.com/changelogs/pool/<component>/<prefix>/<source>/<source>_<version>/changelog`
  (observed layout, e.g. `pool/main/c/curl/curl_8.14.1-2ubuntu1/`), and Launchpad
  `https://launchpad.net/ubuntu/+source/<source>/<version>`. A changelog file is the
  concatenation of stanzas `source (version) suite; urgency=...`, so the excerpt between the
  locked version and the candidate version is a simple stanza slice.

### 2.4 SBOM tooling fit

syft catalogs dpkg from a directory and emits CycloneDX offline; grype scans an SBOM
against a local DB ([syft](https://github.com/anchore/syft), [grype](https://github.com/anchore/grype)).
Both need egress for DB refresh, which the hub denies by default. The existing
`packages.txt` already is the dpkg inventory of the fat rootfs; rendering it as CycloneDX
with `purl: pkg:deb/ubuntu/<name>@<version>?arch=<arch>` feeds `Sbom::CycloneDxParser`
(`cyclone_dx_parser.rb:12-16`) unchanged. syft on the forge is optional and only adds
language ecosystems from Class-B content.

### 2.5 Mixed snapshots across the fleet: what collides, and the policy

**Ownership model already in the repo.** A content module's carved file set is its
`package_spec` closure minus `base-os-ubuntu-noble`'s closure, by package name
(`scripts/module-build/derive-file-spec.sh:8-19`); the carve-conformance workflow fails a
module that carves base-owned files (`.gitea/workflows/carve-conformance.yaml`). The shared
floor (libc6, libssl3t64, systemd, curl, ca-certificates, openssh and their closures, from
base-os's 13 top-level packages, `modules/base-os-ubuntu-noble/manifest.yaml:150-182`)
exists in one layer. Modules are unioned by template priority and overlayfs serves the
highest-priority layer per path (`agent/internal/runtime/reconcile.go:704-705`).

Residual collision classes with base-os at T1 and a content module at T2:

1. **Runtime linking against an older floor.** Safe within a release (SRUs keep sonames
   and symbol sets) and checkable: if any package in the content delta declares a minimum
   version of a base-owned package above base-os's lock (versioned `Depends:` from the
   index), base-os must move first or in the same batch.
2. **Sibling overlap.** Packages declared by more than one content module are carved into
   each. Measured today: `jq` in 5 modules, `ca-certificates` in 6 content modules, `git`,
   `rsync`, `uuid-runtime`, `wget`, `tmux`, `iptables`, `docker.io`, `docker-buildx`,
   `postgresql-16`, `postgresql-client-16`, `ncurses-*` in 2 each, `nftables` in base-os and
   `sdwan-overlay`. Two of these on one template at different snapshots serve whichever
   copy has the higher priority, per file; a security fix in one copy can be masked by the
   other. This is the whole masking risk and it is bounded to this list.
3. **Reporting.** Fleet snapshot state must be per module (version row records snapshot
   and lock) and, for overlap groups, per template.

**Policy:** base-os moves on its own cadence and content tracks its own closure (a base
move never rebuilds content, because it does not change a content closure); the floor
invariant (`as_needed`: base-os joins a batch only when class 1 requires it; or
`always_newest`: base-os is never older than any content module) is enforced by the
candidate evaluator; overlap groups on a template move together, and the long-term fix is
one provider module per shared package (the dep-graph-aware exclusion in
`ci-compute-dirty-closure.sh:302-337` was written for that split); vendor-repo modules are
outside the snapshot and are handled by cadence or a vendor-index diff (Q5).

## 3. Recommended methodology

### 3.1 Ingest the lock at publish (Rails, ~150 lines)

In `ModuleOciIngestService` fetch the `module.packages` layer next to the erofs descriptor
(`module_oci_ingest_service.rb:432-447`), parse `name\tversion\tarch`, write
`ModuleArtifact.sbom_packages_data` in the existing `{name, version, ecosystem: "deb",
purl}` shape plus `sbom_packages_synced_at`, and record `apt_snapshot` and the packages
sha on the version row. `ExposureCalculator` immediately switches to SBOM matching for
native modules. One-shot backfill for current versions. Prerequisite for everything below.

### 3.2 Candidate evaluator (Rails + worker, ~500 lines, shared by both lanes)

`System::SnapshotCandidateService.evaluate!(timestamp:, lane:, scope:)`:

1. Fetch T2 indices via `AptAdapter` (transient repository struct at `<base>/<T2>/`, no
   `System::Package` rows), build `{[name, arch] => {version, pocket, source, depends}}`.
2. For every module version in scope, `delta = [{name, from, to, pocket, source}]` by
   comparing the lock (§2.2 method 1).
3. Confirm each flagged module with the private-state `apt-get -s` resolution
   (§2.2 method 2, reusing `derive-file-spec.sh`'s technique; needs apt on the worker
   host). A module whose simulated closure is unchanged is dropped.
4. Apply the §2.5 policy: floor check (base-os pulled in when a delta's versioned
   dependencies need it), overlap groups per template, base-os flagged by its own delta
   only. Each planned module carries a reason: `own_delta`, `floor_required_by:<m>`,
   `overlap_group:<pkg>`.
5. Enrich every delta entry: pocket; USN/CVE ids from the OSV feed where
   `from < fixed <= to`; version classification (§3.4.1); changelog excerpt and links
   (§2.3). Classify the module's delta as `security` (any entry from `noble-security` or
   closing a USN) or `feature` (everything else).
6. Persist `System::SnapshotCandidate` (`lane`, `timestamp`, `evaluated_at`, per-module
   deltas JSON, `security_count`, `cve_ids`, `usn_ids`, `status:
   reported|approved|dispatched|declined`) and emit `system.snapshot_candidate_reported`.

Knobs (SiteSettings): `system.apt_snapshot.floor_modules` (default
`base-os-ubuntu-noble`, plus `powernode-system-base` if it carries packages),
`system.apt_snapshot.floor_rule` (`as_needed|always_newest`), and the per-lane knobs below.
A 5xx from the snapshot host is "no evaluation", never "no delta".

### 3.3 Security lane: highest priority, fast, automatic

**Inputs and cadence**

- `FeedIngestService` source `ubuntu-osv` (~120 lines): the `Ubuntu:24.04:LTS` USN and
  CVE records, run from a `SystemUbuntuOsvFeedJob` every 15 minutes (offset from the
  hourly NVD job at `worker/config/sidekiq_system.yml:60-64`). Writes/updates `System::Cve`
  rows with deb `affected_packages` (name, fixed version, ecosystem `deb`); the existing
  `ExposureCalculator` + `VersionMatcher` then produce `open` exposures against the
  ingested locks.
- `noble-security` index watch, every 15 minutes in the same job: fetch only
  `dists/noble-security/{main,universe}/binary-<arch>/Packages.xz` at `now` (a few MB) and
  diff against all locks. This catches a security publication even before its OSV record
  lands, and it is authoritative for "the fix is actually downloadable".

**Trigger and candidate**

- A candidate is evaluated when (a) an `open` exposure appears whose fixed version is
  present in the security-pocket index, or (b) the index watch finds a lock entry with a
  newer `noble-security` version. T2 = the evaluation instant floored to the minute. If
  the fixed version is not yet in the T2 index (mirror propagation), the candidate is
  retried next tick instead of planning a build that would not contain the fix.
- Scope = modules whose lock contains a vulnerable binary, plus floor and overlap groups.
  Modules without a security delta are never planned by this lane.

**Dispatch**

- Auto-dispatch behind a dedicated action category `release.security_build_dispatch`,
  seeded `auto_approve`, declared alongside the existing `release.build_dispatch`
  (`system_fleet_tool.rb:517`; category list in core's
  `ai/engineering/release_dispatch_floor_seeder.rb:88`, policy defaults in
  `ai/intervention_policy.rb:37`). A separate category so the operator can flip the
  security lane to `require_approval` without touching manual dispatches, and vice versa.
- Batch: `trigger: snapshot`, `metadata: {lane: security, snapshot_candidate_id, apt_snapshot,
  cve_ids, usn_ids, modules: [{name, reason, packages: [{name, from, to, pocket}]}]}`.
  The same fields are the operator report. Reuse the existing `cve` trigger value for
  these batches if you prefer the label to finally mean something.
- Riders: a snapshot pin is all-or-nothing per module, so the module also takes every
  `noble-updates` change to its closure since its previous pin. The batch metadata lists
  riders with their classification; `system.apt_snapshot.security_lane.rider_policy`
  (`accept|park_on_major`, default `accept` because security is the priority) decides
  whether a batch containing a `major`/MRE rider still auto-dispatches or parks for
  approval with the report attached (§3.4.3).

**"Fast", end to end, content modules (1 to 3 modules, default builder cap 2)**

| Step | Budget |
|---|---|
| USN/pocket publication to detection (15-minute feed + index watch) | 0 to 15 min |
| Candidate evaluation (index fetch, diff, `apt-get -s` confirm, OSV join) | 1 to 3 min |
| Approval (auto) | 0 |
| Build (3 to 8 min per module, 2 concurrent; raise `max_concurrent_builders` for security batches if the forge pool allows) | 5 to 15 min |
| Publish, sign, ingest lock | 1 to 2 min |
| Soak on a canary instance (§3.6) | 30 min default |
| Promotion release, agent sync, `restart_after_update` | 1 to 5 min |
| **Total** | **~40 to 70 min typical, under 2 h at the tail** |

**Hub modules (hub-backend, hub-worker, hub-frontend, extension-system): ordering and holdback**

- They are Class-B: their build clones core from the build remote
  (`memory/build-clones-core-from-stale-github-mirror.md`). A security batch must pin
  `CORE_REF` to the currently promoted core commit (per-batch pin exists,
  `node_api/config_controller.rb:599`), never to the remote's HEAD, or the security fix
  ships unreviewed core changes.
- Core and extension modules in one batch are already promoted as a unit by the holdback
  (`native_module_build_orchestrator.rb:1090`); a partial batch promotes nothing. Content
  modules in the same batch are released first; hub modules last.
- Promoting a hub module restarts the sole control plane: `/up` 502 for up to about 3
  minutes and MCP (including the cancel and rollback verbs) unreachable for that window
  (`memory/deploy-boot-502-window-and-mcp-blackout.md`). Rules: never release a hub
  promotion while another batch is in flight; never inside the boot window of a previous
  release; default to **operator release** for hub modules with the report attached, with
  an optional timed auto-release inside a configured window (Q3).

### 3.4 Feature lane: infrequent, changelog-driven, operator-decided

**Cadence:** monthly, first Tuesday 02:00 UTC, `SystemSnapshotFeatureCandidateJob`; plus an
on-demand verb `system_evaluate_snapshot_candidate(timestamp:, modules:)`. Scope = all
modules; T2 = the job instant.

#### 3.4.1 The per-module report

For each module, for each changed package in its confirmed closure delta:

| Column | Source and rule |
|---|---|
| package, from, to | lock vs T2 index |
| pocket | which of `noble`, `noble-updates`, `noble-security` supplies `to` (backports is not enabled by mmdebstrap and is not proposed) |
| classification | Debian version semantics: split `[epoch:]upstream[-revision]`; if `upstream` unchanged: `packaging` (an SRU revision bump, e.g. `-2ubuntu10.5` to `-2ubuntu10.6`: bugfix or security); else compare `upstream` dot-components: first differs `major`, second `minor`, else `patch`; mark packages known to receive micro-release exceptions (`postgresql-16`, `docker.io`, and any the operator lists) |
| feature vs bugfix evidence | changelog stanzas between `from` and `to`: LP bug references and "SRU" wording read as bugfix, "New upstream release"/version-only stanzas as feature, `CVE-` references as security. Presented as evidence with the excerpt, not as a verdict |
| changelog | excerpt (first N lines of the stanzas between `from` and `to`) plus links to changelogs.ubuntu.com and Launchpad (§2.3) |
| CVEs closed | USN/CVE ids where `from < fixed <= to` |

Module-level summary: counts by classification, whether the module is in an overlap
group, whether the floor check pulls base-os in, estimated build minutes from the last
build, and the riders it would take if only a subset of the report is wanted.

**Nothing builds.** The candidate stays `reported` until the operator selects modules in
the UI or via `system_dispatch_snapshot_candidate(candidate_id, modules: [...])`, which is
gated on `release.feature_build_dispatch` seeded `require_approval`.

#### 3.4.2 Partial acceptance: what a snapshot pin can and cannot express

A snapshot pin is per module and all-or-nothing: the module's whole closure resolves at
T2 or stays at T1. **Per-package cherry-picking is not possible with a pin.** The
operator's unit of decision is the module. The closest achievable forms, in order of
recommendation:

1. **Decide per module.** Accept module A at T2 (all its changes), leave module B at T1.
   This is what the report is built for and needs nothing new.
2. **Hold features, take security: per-module pocket set.** Add `build.apt_pockets:
   [release, security]` (default `[release, updates, security]`) so Stage 1 writes the
   chroot sources with only `noble` and `noble-security`. Ubuntu builds security updates
   in a security-pocket-only environment, so a `release+security` configuration is
   supported upstream. A module held in the feature lane keeps taking security fixes on
   the security lane without any `noble-updates` riders. Cost: a Stage 1 change (~30
   lines in `stage1-rootfs.sh`, passing explicit sources to mmdebstrap instead of the
   bare suite), which is baked into module-forge and so needs one forge rebuild; and
   such a module misses SRU bugfixes until the feature lane accepts it.
3. **Pin one package back: per-module apt preference.** `build.apt_pins: [{package,
   version}]` rendered into `/etc/apt/preferences.d` in the chroot. Only versions that
   still exist in the T2 index are pinnable: the release-pocket (GA) version and the
   current `-updates`/`-security` versions, not an arbitrary intermediate one. Useful for
   a single problematic package; brittle beyond that.

#### 3.4.3 When both lanes touch the same module on the same snapshot

- The security lane moves module M to T2 for a fix; M's `noble-updates` riders come
  along. The candidate lists them, classified. Under `rider_policy=accept` the batch
  auto-dispatches and the feature report for M next month has nothing left to show;
  under `park_on_major` a batch with a `major`/MRE rider parks for approval with the
  report, and the operator either accepts it (fix plus riders) or switches M to the
  `release+security` pocket set (3.4.2 form 2) so the fix ships without the rider.
- A feature-lane acceptance of M at T2 also clears any pending security candidate for M.
- One in-flight batch per module: `deferring_batch_for`
  (`module_publication_processor.rb:371-381`) already finds a module's in-flight batch;
  the evaluator refuses to plan a module that has one and re-evaluates it when the batch
  settles.
- Both lanes write the same `SnapshotCandidate` model with `lane` set, and both dispatch
  through §3.5, so the report shape and the audit trail are identical.

### 3.5 `snapshot` batch trigger, explicit plan, no fan-out (Rails, ~250 lines; one bot commit per batch)

Where it plugs in: **not** into `plan_with_diagnostics`' path rules. The path rules and
`expand_reverse_dependencies` are the fan-out. Follow `PackageClosureBuildBridge`, which
creates a batch from an explicit plan (`package_closure_build_bridge.rb:98`,
`ModuleBuildBatch.create_for` at `module_build_batch.rb:165`):

1. Add `snapshot` to `ModuleBuildBatch::TRIGGERS` (`:38`); the orchestrator already
   branches on trigger for the manifest step (`:1258`).
2. `SnapshotCandidateService.dispatch!(candidate, modules:)`:
   - **Option A (manifest is truth, recommended):** commit one change to the system repo
     setting `build.apt_snapshot: <T2>` on exactly the planned manifests, push, create the
     batch with `head_sha` = that commit and `trigger: snapshot`. The forge drift guard
     passes, the inputs hash sees the new pin, git history records the increment, and a
     later `develop` push does not re-plan the catalog. Needs a bot push token for the
     system repo (the forge holds a read token today; the write grant is the one new
     credential).
   - **Option B (batch context is truth):** pass `apt_snapshot` through the per-module
     batch context (already forwarded, `native_module_build_orchestrator.rb:902`), relax
     the drift guard for `trigger: snapshot`, record the effective snapshot on the version
     row only. No commit, but the manifest then lies about what was built and an ordinary
     push rebuilds the module at the old pin.
3. The plan is exactly the candidate's planned set; no expansion by construction;
   `metadata` carries lane, candidate id, CVE/USN ids and per-module packages.

### 3.6 Promotion, soak, canary

- Batch-atomic holdback already exists for `planned_count > 1`; keep the rule that a
  partial batch promotes nothing.
- There is no per-instance module canary today (`Honeypot::CanaryModuleService` is a
  honeypot; templates cannot pin a module version: no such column on `TemplateModule`).
  Minimal real soak (~150 lines): a `canary_instance_ids` set per template; the node API's
  module sync serves the batch's held versions to those instances while
  `current_version_id` still points at the old ones; the orchestrator releases the deferred
  promotions when every canary has reported the new digest and healthy units for
  `soak_minutes` (default 30), and holds them with an event otherwise. Until that lands,
  soak means a timed hold for content modules and operator release for hub modules.
- Build base-os first when it is in a batch, so a partial failure leaves the floor moved
  and content unmoved, the direction the floor invariant tolerates.

### 3.7 What the operator sees

- MCP: `system_list_snapshot_candidates(lane:, status:)`,
  `system_get_snapshot_candidate` (the §3.4.1 report), `system_evaluate_snapshot_candidate`,
  `system_dispatch_snapshot_candidate(candidate_id, modules:)`,
  `system_release_held_promotions(batch_id)` for hub modules.
- UI: a "Base packages" tab on the modules page: per module snapshot, lock age, open
  version-confirmed CVEs, latest security and feature candidates, overlap group and floor
  status; a candidate detail view with the per-package table and changelog excerpts.
- Fleet events: `system.snapshot_candidate_reported`, `system.snapshot_batch_dispatched`
  (with CVE/USN ids), `system.promotions_held` (already exists).

### 3.8 What changes where

| Layer | Change | Section |
|---|---|---|
| Scripts (`scripts/module-build/*`) | none for the core loop; optional `build.apt_pockets` / `build.apt_pins` in Stage 1 (~30 lines each) for 3.4.2 forms 2 and 3; delete the trixie-based `apt-closure-sha256` once 3.1 lands | 3.4.2 |
| Forge (`module-forge-build.sh`, buildenv) | none for the core loop; one forge rebuild if Stage 1 changes; the filed offers (persistent apt cache `01a0813c-9f06`, Stage 1 base artifact `01a0813c-c26b`) make the remaining rebuilds cheaper and less upstream-dependent | 3.4.2 |
| Rails (system extension) | ingest, evaluator, OSV feed, classification + changelog fetch, two policy categories, trigger, canary sync override, verbs, models + migrations | 3.1 to 3.7 |
| Worker (system extension) | three cron entries (OSV feed + security watch, monthly feature candidate) and their `worker_api` endpoints; apt on the worker host for the confirm step | 3.2 to 3.4 |
| Core | add the two new categories to `release_dispatch_floor_seeder.rb:88` | 3.3 |
| System repo | one bot commit per dispatched batch (Option A) | 3.5 |

## 4. Risks and anti-patterns (tied to recorded incidents)

- **Do not put snapshot deltas into the path-rule planner.** Any dirty set there is
  expanded over `requires`; a delta on `redis` would rebuild hub-backend and hub-worker.
  That is the 21-module plan from a 2-file diff and the 23-module plan predicted as 4.
- **Do not bump all 31 manifests as the mechanism.** The pin is a hash input; the skip
  cannot help. Bump only the planned manifests (Option A) or none (Option B).
- **A security batch must not ship unreviewed core.** Class-B modules inherit whatever
  core is on the build remote; pin `CORE_REF` to the promoted core commit.
- **Partial batches and hand-promotion recreate the 2026-08-28 skew.** The holdback
  promotes nothing on a partial batch; the report must say which held versions form a set.
- **Building is deploying, and the kill switch is dark during a hub restart.** Auto
  dispatch is confined to content modules by default; hub promotions are operator-released
  outside any in-flight batch and any boot window.
- **Do not derive freshness from the runner's apt** (the trixie `apt-closure-sha256`).
  Read the noble snapshot indices or the module's own lock.
- **A `suspected` exposure is not evidence.** Until 3.1 lands, dashboard CVE counts say
  nothing about versions; the security lane must key on version-confirmed exposures and
  the security-pocket index, never on keyword rows.
- **Single upstream.** Candidate evaluation and every rebuild depend on the snapshot host
  (today's outage). A 5xx is "no evaluation"; the base-artifact offer removes the per-build
  dependency.
- **Riders are real changes.** `rider_policy=accept` means a security batch can carry a
  postgresql micro-release; the report must show it before promotion, and hub/database
  modules deserve `park_on_major` even if content modules run `accept`.
- **Vendor-repo modules cannot be diffed from the snapshot** and must be handled by
  cadence or a vendor-index diff, or they silently never move.

## 5. Clarifying questions for the operator

Settled by the two clarifications and not asked again: stay on noble; per-module drift
with a uniform floor; security lane fast and automatic on CVE/USN and security-pocket
changes; feature lane infrequent, changelog-driven, operator-decided; report before build;
full rebuilds are explicit exceptions. Still open:

1. **Floor rule.** `as_needed` (base-os joins a batch only when a content delta's versioned
   dependencies require it) or `always_newest` (base-os is never older than any content
   module, so it moves on every security increment)?
2. **Rider policy for the security lane.** When a security fix rides with a `major`/MRE
   feature change on the same snapshot for one module, auto-dispatch anyway (`accept`), or
   park that batch for approval (`park_on_major`)? May the answer differ for hub and
   database modules versus other content modules?
3. **Hub module release.** After a security batch containing hub-backend/worker/frontend/
   extension-system completes and soaks, operator release only, or a timed auto-release
   inside a configured window (which window)?
4. **Soak.** Is 30 minutes on a canary instance the right default, and is there (or should
   there be) a designated canary instance per template for the soak mechanism in §3.6?
5. **Vendor-repo modules.** For `log-forwarder-vector` and `storage-tools`, rebuild on a
   fixed cadence, diff the vendor index too, or leave them manual?
6. **Security-only pocket set.** Do you want the per-module `release+security` build option
   (§3.4.2 form 2) so a module held in the feature lane still takes security fixes without
   `noble-updates` riders? It is the only way to express "security yes, features no" for a
   module.
7. **Reproducibility unit.** Must `modules/<slug>/manifest.yaml` at the built commit state
   the snapshot actually used (Option A, needs a bot push token for the system repo), or is
   the version row enough (Option B, no commit)?
8. **Class-B core pin.** Confirm that security-lane batches for hub modules pin core to the
   currently promoted core commit rather than the remote's default branch.
9. **Feed egress.** Is egress to Canonical's OSV metadata host (or a mirrored tarball) and to
   changelogs.ubuntu.com acceptable on the hub's default-deny egress?
10. **Overlap groups.** When a shared package (e.g. `jq` in five modules) has a delta, is
    rebuilding the co-mounted group acceptable, or should shared packages first move into
    single provider modules?
11. **Boot image.** Should the boot image (`initramfs`, own pin `20260430T000000Z`) join the
    security lane and follow base-os's snapshot, or stay on its own manual pin?
12. **Feature cadence.** Monthly on the first Tuesday 02:00 UTC, or a different rhythm or
    maintenance window?

## 6. Sources

- Ubuntu snapshot service: <https://ubuntu.com/server/docs/how-to/software/snapshot-service/>
- Debian snapshot semantics: <https://snapshot.debian.org/>
- mmdebstrap(1) (automatic `-updates`/`-security` for stable suites): <https://manpages.debian.org/trixie/mmdebstrap/mmdebstrap.1.en.html>
- apt-get(8) noble: <https://manpages.ubuntu.com/manpages/noble/en/man8/apt-get.8.html>
- apt.conf(5) noble (`RootDir`, `Dir::*`, `Debug::NoLocking`): <https://manpages.ubuntu.com/manpages/noble/en/man5/apt.conf.5.html>
- Ubuntu OSV data: <https://documentation.ubuntu.com/security/security-updates/osv/>
- Ubuntu OVAL data: <https://documentation.ubuntu.com/security/security-updates/oval/>
- Ubuntu changelogs layout: <https://changelogs.ubuntu.com/changelogs/pool/main/c/curl/>
- syft: <https://github.com/anchore/syft>; grype: <https://github.com/anchore/grype>
- In-repo: files cited inline under `extensions/system/` and `server/`; incident notes are
  the maintainer's auto-memory (`memory/*.md`, not tracked).

## 7. Operator decisions (2026-09-08)

Answers to §5, recorded verbatim in intent; they bind the campaign that implements this document.

| # | Question | Decision |
|---|---|---|
| 1 | Floor rule | `as_needed` — base-os joins a batch only when a content delta's versioned dependencies require it |
| 2 | Rider policy | `park_on_major` for hub (backend/worker/frontend/extension-system) and database modules; `accept` elsewhere, riders listed |
| 3 | Hub release | operator release only after soak |
| 4 | Soak | **active health gate, not a timed hold**: agent liveness, module units active with no restart loop, `/up` + MCP `tools/list` for hub modules, platform_resilience / compliance_snapshot sensors green, error-rate and log-signature regression check against the previous version; failure = automatic hold and canary rollback. Designated canary instance per template. |
| 5 | Vendor-repo modules | diff the vendor index too; same lanes |
| 6 | Security-only pocket set | yes — per-module opt-in `release+security` pocket selection (Stage 1 change + one forge rebuild) |
| 7 | Reproducibility unit | Option A — pin bump committed to the planned manifests by a bot before dispatch |
| 8 | Class-B core pin | confirmed — security-lane hub batches pin core to the promoted core commit |
| 9 | Feed egress | allow-list the OSV/USN feed host and changelogs.ubuntu.com on the hub |
| 10 | Overlap groups | rebuild the co-mounted group now; follow-on to consolidate shared packages into single provider modules |
| 11 | Boot image | security lane, follows base-os's snapshot; feature-lane changes stay manual |
| 12 | Feature cadence | monthly, first Tuesday 02:00 UTC, plus on demand |

Standing policy (from the same day): stay on noble (no 26.04 migration now); security updates are highest
priority with fast deployment, especially on CVE reports; normal package updates happen on an infrequent
schedule and are evaluated and decided independently per changelog / feature / major-vs-minor.
