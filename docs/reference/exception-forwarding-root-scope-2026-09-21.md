# Exception-forwarding scanner: rescoped root set and per-root counts (IMP-6c8ad340c334)

**Status: scope + count only, per operator direction. Nothing in this task's findings has been
fixed. Remediation is offer `01a0c0e8-a8f1` (the sweep; pending approval — it has no `IMP-` key
until approved), which runs after this task and takes this doc as its input.**

## Decision this doc applies (settled, not re-derived here)

Root = **files that can write a provider-facing result envelope**: `error_result(`/`success_result(`
producers, plus `processing_metadata` writers (the `ai_messages` column persisted and replayed to
the model provider) — excluding controller-boundary files, which answer an authenticated
HTTP/frontend user, a different trust boundary already classified in IMP-bbb881b3e4f7 and
IMP-378de6e082be. This supersedes both the too-narrow `ai/tools`-only root used historically and
the too-wide whole-`server/app`-tree root an earlier version of this offer proposed; both
retractions are the operator's own correction, not re-litigated here.

## Method — the root-set command

Run from `/home/pnadmin/worktrees/loop-merge`:

```
A: command grep -RlE 'error_result\(|success_result\(' server/app extensions/system/server/app 2>/dev/null | command grep -v '/controllers/' | sort -u
B: command grep -RlE 'processing_metadata' server/app extensions/system/server/app 2>/dev/null | command grep -v '/controllers/' | sort -u
ROOT = sort -u of (A ∪ B)
```

`A` = 90 files, `B` = 12 files, overlap = 6, union = **96 files**. Independently re-run from
scratch (not just re-read from a saved list) immediately before writing this doc — `diff` against
the saved working list was clean.

Split: **87 core** (`server/`) + **9 extension** (`extensions/system/`). Of those, **66 core +
8 extension** sit inside an `ai/tools/` tree; **21 core + 1 extension** sit outside it. (This
corrects an earlier draft of this count that misstated the core/extension totals as 88/8 while
its own sub-splits, 66+21 and 8+1, already summed to 87/9 — the sub-splits were right, the
top-line table wasn't. Verified here directly from the saved file list with `wc -l`, not by
re-adding the earlier wrong cells.)

## What the `-v '/controllers/'` filter actually removed, and why (do not attribute by path alone)

The unfiltered union (before excluding controllers) is 100 files; the filter removes exactly 4.
Each is classified below by what it actually matched, not by its directory name — a file under
`.../controllers/` still needed its match read before its exclusion could be called correct.

| File | What it matched | Real producer? | Verdict |
|---|---|---|---|
| `server/app/controllers/api/v1/ai/conversations_controller.rb` | Real `processing_metadata:` write (`:300`, in the assistant-message-creation branch) | Yes | Correctly excluded — genuine controller-boundary (browser-authenticated) producer, out of scope for the provider boundary this root targets. |
| `server/app/controllers/concerns/ai/conversation_management_actions.rb` | Real `processing_metadata:` writes (`:129`, `:147`) | Yes | Correctly excluded, same reason. Included only by `conversations_controller.rb` (`command grep -rl 'ConversationManagementActions' server/app/controllers/` returns exactly that one file) — same boundary, not a separate one. |
| `extensions/system/server/app/controllers/api/v1/system/platform/peer_grants_controller.rb` | A **comment** (`:175`, "`.processing_metadata` nor the role:"tool" message forwarded to the ...") describing behavior elsewhere, not a call | **No** — comment-only match | Was never a real producer; the controller-boundary rationale is not even the operative reason for its exclusion. `< ApplicationController` + `before_action :authenticate_request`, and its own header comment says it "mirrors the dashboard's drill-down" — this is the operator/browser boundary, not a peer-signed MCP boundary, contrary to a concern raised about it; confirmed by reading the class, not inferred from the path. |
| `extensions/system/server/app/controllers/api/v1/system/platform/storage_migrations_controller.rb` | A **comment** (`:158`, "`BaseTool#success_result(data)` wraps its argument as...") describing a design note, not a call | **No** — comment-only match | Same as above: never a real producer under this criterion; filtering it via the controller carve-out was coincidental, not the true reason. Also `< ApplicationController` + `authenticate_request`, operator/browser boundary. **Separately worth flagging (not fixed, out of scope):** this controller's `call_mcp_action` has its own genuine `rescue StandardError => e ... { success: false, error: e.message }` leak — but it is a browser-boundary leak, not a provider-boundary one, so it is correctly outside this root and is not part of this task's count. |

Confirmed separately: `mcp/streamable_http_controller.rb` (fixed in `3cbdbcced`) is **not** among
the 4 removed files — the controller filter does not silently drop the file this family just
fixed.

## Coverage boundary this root does NOT close — state as unanswered, not resolved

This task's own motivating discovery was 16 `e.record.errors` hits in `extensions/system` outside
`ai/tools`. Enumerating the distinct files that raise that pattern outside `ai/tools`:

```
command grep -RlE 'e\.record\.errors' extensions/system/server/app/ | command grep -v '/services/ai/tools/'
```

returns **12 files**. Intersecting that list against this task's own root criterion
(`error_result(|success_result(|processing_metadata`) returns **zero** — none of the 12 are
envelope producers under criterion (c):

- `agent_module_commit_service.rb`
- `gitops/apply_service.rb`
- `manifest_import_service.rb`
- `module_oci_ingest_service.rb`
- `module_skill_registrar.rb`
- `node_enrollment_service.rb`
- `platform_deployment_service.rb`
- `volume_management_service.rb`
- `ai/skills/disk_image_retention_executor.rb`
- `ai/skills/expose_service_local_executor.rb`
- `ai/skills/expose_service_public_tcp_executor.rb`
- `ai/skills/gitops_register_repository_executor.rb`

(all under `extensions/system/server/app/services/system/`). The extension's single non-`ai/tools`
file that IS in this task's root, `module_build_parity_service.rb`, is not one of these 12 —
confirmed by set difference, not assumed.

This is not a defect in the root decision — criterion (c) is settled, and a service returning a
plain string that some *other*, later caller wraps into an envelope is not itself an envelope
writer. But it means: **the rescoped root, applied exactly as specified, excludes 100% of the
files that motivated the original offer.** Whether those 12 services' error strings reach the
model provider through whatever calls them is an open, unanswered reachability question — it is
explicitly **not answered by this task**. It has been filed as offer `01a0c1b7-d502` (pending
approval; it has no `IMP-` key until approved) so it does not get answered inside this task.

## Per-root scanner counts

Every run below invoked `ruby scripts/audit/exception_forwarding_scan.rb <files>` directly with
its own exit status checked immediately (not through a pipe — `$?` after a pipe belongs to the
last command in it, not the scanner). All six runs below exited **0** — no conservation-tripwire
violation.

| Root | files | RAW | FORWARDED-BY-INTENT | SANITIZED | TOTAL |
|---|---|---|---|---|---|
| full 96-file union | 96 | 193 | 31 | 115 | 339 |
| core (`server/`) | 87 | 123 | 31 | 115 | 269 |
| extension (`extensions/system/`) | 9 | 70 | 0 | 0 | 70 |
| `ai/tools/`, core | 66 | 47 | 31 | 115 | 193 |
| `ai/tools/`, extension | 8 | 68 | 0 | 0 | 68 |
| outside `ai/tools/`, core | 21 | 76 | 0 | 0 | 76 |
| outside `ai/tools/`, extension | 1 | 2 | 0 | 0 | 2 |

Reconciliation (three independent additions, all closed):

- core-tools + core-other = 47+76 = 123 RAW / 31+0 = 31 FWD / 115+0 = 115 SAN — matches the core row.
- ext-tools + ext-other = 68+2 = 70 RAW / 0+0 = 0 FWD / 0+0 = 0 SAN — matches the extension row.
- core + extension = 193 RAW / 31 FWD / 115 SAN — matches the full-union row.

**Headline finding (report only, not touched):** extension code (9 files total) shows zero
FORWARDED-BY-INTENT and zero SANITIZED hits across this entire producer set — every one of its 70
hits is RAW, meaning it never routes through `rescued_error_result` anywhere in this set. Core, by
contrast, already has 146 of its 193 non-RAW hits sanitized or forwarded-by-intent. This is the
correct input for the sweep: core has an established pattern to extend; the extension has none to
extend yet.

## Discrepancy against the offer's own "~64 files" figure — only partly explained, not closed

The offer's own text estimated "~64 such files, only ~16 outside `ai/tools`." This task's
reproducible measurement is 96. Do not read the following as closing that gap — it only accounts
for part of it:

- `A` alone (the `error_result(`/`success_result(` producers, non-controller) = 90 files.
- The `processing_metadata`-only additions (`B`, non-overlapping with `A`) = 6 files.
- 90 is itself already larger than the offer's ~64, and 64 + 6 = 70, not 96.

**This leaves roughly 26 files unaccounted for.** Neither the `processing_metadata` criterion
extension nor the controller carve-out (which removes files, making the gap larger, not smaller)
explains it. Possible causes not investigated here, because investigating them would be
re-deriving a decision this task was told to apply rather than re-litigate: the offer may have
used a narrower or differently-worded grep pattern, may have miscounted, or the codebase may have
grown between when the offer was filed and now. **Stated as: the earlier ~64 figure is not
reproducible from criterion (c) as specified, and the ~26-file remainder of the difference is
unexplained** — not resolved, and not to be read as resolved.
