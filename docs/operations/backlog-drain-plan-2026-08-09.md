# Backlog Drain Plan — `dev-loop/dev-improve` → `develop`

**Date**: 2026-08-09 · **Approved approach**: operator chose "plan a full drain" (this doc);
landing itself is supervised, batch by batch.
**State at writing**: core branch forward-merged with develop at `819b497c7`
(develop `27a2bd69b` = v58 deploy). Un-landed: **28 core commits** (`git cherry` `+`;
the other 18 are cherry-equivalent to develop) and **43 extension commits**
(`extensions/system` `origin/develop..b0b77979`; 2 cherry-equivalent).

## Ground rules (from memory + conventions)

- Land per BATCH: ff-merge or cherry-pick set → full gate (`scripts/validate.sh`) →
  push Gitea + GitHub → deploy step if live-relevant. Never one monolithic land.
- **Any batch adding permissions MUST run `Role.sync_from_config!` on the live DB at
  deploy** (owners/admins 403 otherwise; rspec cannot catch it).
- **Any batch with migrations**: `rails db:migrate` on live immediately (never leave pending).
- The gate does NOT run extension specs — extension batches need the extension's own
  suite run explicitly (in the main checkout or a prepared worktree, NOT a bare one).
- Extension lands go **inside the submodule first**, then bump the parent pointer.
- Extension repo pushes to BOTH origin (Gitea) and github; never `git submodule sync`.

## Core batches (28 commits, in land order)

1. **MCP surface + permissions** — `92a7b2d84` (declare `system.module_builds.cancel`),
   `6f9e0db36` (route rollback tool), `33b48ad51` (close data plane to instance
   principals), `254cdad68` (enforce `ai.introspection.view`).
   Deploy: `Role.sync_from_config!` required. Verify MCP tool advertisement
   (core all_tools allowlist) for the two new routes.
2. **GitRunner lifecycle saga (squash-review)** — `faf33402c` → `7404c490b` →
   `be18ecebc` (revert) → `fb00c85ed` (inventory + local-signal prune) → `588b6041d`
   (pointer + prune-script FK fix). Net effect is the LAST state; review as one diff.
   The intermediate revert chain must not land as-is without review — it deleted live
   runners three ways before being corrected.
3. **Autonomy sensors/OODA** — `59ccd5cfb`, `cc6978f8e`, `12d8a3fa1`, `577b6738e`,
   `d24fe326e` (server-side pass adjudication), `47d68f0a9` (OODA closure driver,
   default OFF — verify the flag is still OFF at land).
4. **Learning/skills** — `0dcada2e2`, `0002f3ff3`, `2746429bd` (embedding-first
   query_learnings), `a916eaf9b` (per-account KG copies), `126db3f72`
   (SkillMutationService rebuild), `3a98c1842` (binding seed), `36af49726` (worker).
   Worker commit means worker deploy + restart too.
5. **Security-scan scoping** — `52065898e` + `2e8f7e9eb` (MCP payload exemption).
   Small; review the exemption pattern against current scan behavior.
6. **Schema chores** — `08c093e39` (`system_node_modules.auto_promote`), `18bd4bc45`
   (`last_sync_attempted_at`). Migrations → live `db:migrate` at deploy. These pair
   with extension batches E2/E3 below — land together.
7. **Module Builds tab (frontend)** — `11153c6e3` (+ depends on batch 1's cancel perm).
   `npx tsc --noEmit` + jest; verify against the extension E2 batch (cancel endpoint).
8. **Review-findings sweep** — `49e50771e` (fixes to already-landed work) — can ride
   with batch 4.
9. **Docs** — the dryrun protocol/report/plan docs ride with any batch.

## Extension batches (43 commits, inside `extensions/system`)

- **E1 module-publish/build safety** — `70c3b7c3` (batch kill switch), `070a801a`,
  `cd56dbb9` (never promote empty artifact), `2fbd1d6a`, `42d927d0`, `e0d295bd`,
  `7e231f0e` (auto-promote holdback → pairs with core batch 6's `auto_promote`
  column), `869e2338`, `bf67ef0b` (real promoted outcome). High value: these are the
  fan-out/kill-switch lessons mechanized.
- **E2 builds cancel + MCP** — `f91741a8` (cancel endpoint; pairs with core batches 1+7).
- **E3 fleet/instances** — `42d927d0`-adjacent fleet actuation, `f48a26a3`, `4a233c18`,
  `54a80a15`, `8dbd66ca`, `544f23ad`, `72e25551`, `8b41f854`, `0e398c4d` (dead-code
  delete), `53fa9435`.
- **E4 gitops + fulfillment fencing** — `b5df4170`, `bbad05f4`, `8a8bbd6b`, `a20e831b`,
  `1d2c1f2f`, `99254e7e`, `6e62c262`, `59bd7c64`, `932f9bf3` (ControlPlaneRole fence).
- **E5 templates/pools/modules refactors** — `18216387`, `d543d999`, `dfe65159`,
  `4b50edf5`, `e286f1c2`, `eeaf3993`, `d40b3732`, `4b6c501e`, `6623cb64` (comment
  scrub — check against core-purity rules), `11d0cf66`, `89e77bfc` (agent test
  sandboxing), `f8132e8d`, `e1936421`, `3af51c33`.

Each E-batch: run the extension suite (≈608 examples) + any Go agent tests touched
(`-count=1` — go test caches live-host probes), commit inside the submodule, land to
extension develop (both remotes), THEN bump the parent pointer in the paired core batch.

## Sequencing

E1 → core 1 → E2 → core 7 → core 2 → core 6+E3 (schema+fleet) → core 3 → core 4+8 →
E4 → E5 → core 5 → docs. After each land: ops-hub deploy only when the batch is
live-relevant (most are); hub-backend rebuild via the recipe, reconciler applies,
verify process-start > file-mtime.

## Risks

- The extension branch and extension develop have DIVERGED lineages (cherry-picks:
  `bee05c74`→`a481cc55`, `b0b77979`→`cf625797`). First step of E1 is a forward-merge of
  extension develop into the extension branch, mirroring what was done for core today.
- Batch 2's history contains a revert-of-a-revert; land the NET diff after review.
- `47d68f0a9` (OODA driver) and `7e231f0e` (auto-promote holdback) change autonomy
  posture — confirm flags/defaults with the operator at land time.
