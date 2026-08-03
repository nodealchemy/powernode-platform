# Code Index Retrieval Quality — Evaluation 2026-08-02

Assessment of whether `code_semantic_search` lets an AI agent **discover code it
cannot already name**. Run against the freshly rebuilt platform index
(89,203 entities, 100% embedded, ops-hub, hub-backend v36).

**Verdict: the index behaves as fuzzy *symbol* search, not semantic search.**
Queries that reuse vocabulary from the identifier or file path succeed. Queries
that describe behaviour in different words fail — even when the target code is
indexed and healthy. The tool advertises "Finds code by meaning, not just name";
in practice the second half of that sentence is the operative one.

## Probe results

Ground truth known independently (code read directly in the same session).

| # | Query | Expected | Result |
|---|-------|----------|--------|
| 1 | "let internal service-to-service calls bypass the anonymous abuse heuristics" | `RequestInspector#trusted_path?` | **MISS** — returned security_gate/anomaly services, ~0.44 |
| 2 | "escalate the ban duration for repeat offenders" | `#calculate_block_duration` | **PARTIAL** — rank 3 `increment_offense_count`; ranks 1–2 matched the token "escalate" in `PolicyViolation#escalate!` |
| 3 | "generate the systemd unit name for a module service" | `agent/internal/lifecycle/service.go` | **MISS** — Go absent (see Coverage) |
| 4 | "instance pool reaper terminate drained members" | `InstancePoolReaperService`, `#terminate_member` | **HIT** — all 3 correct, ~0.55 |
| 5 | "immediately stop a runaway autonomous agent from taking any further action" | `KillSwitchService#emergency_halt!` | **MISS** — returned `execution_cancel`, `abandon!` |
| 6 | "kill switch emergency halt" | same as #5 | **HIT** — 0.60, perfect top-3 |
| 7 | "middleware that blocks suspicious IP addresses" | `RequestInspector#blocked?` | **HIT** — top-2 exact |
| 8 | "batch embedding generation for code index" | `IndexingService#generate_embeddings` | **HIT** — rank 1 |

Behavioural paraphrase: **0 clean hits / 4**. Lexical overlap: **4 / 4**.

Probes 5 and 6 are the controlled pair — same target, same index, same session.
Naming it works; describing it does not.

## Root cause

`IndexingService#generate_embeddings` embeds `"#{node.name} #{node.description}"`,
and `description` is generated structural metadata, not semantics:

    method `emergency_halt!` — in server/app/services/ai/autonomy/kill_switch_service.rb — params: (reason:, triggered_by:)

No docstring, comment, or body text is included. The vector therefore encodes
**identifier + path + visibility + parameter names** and nothing about what the
code does. Measured description lengths: 84,039 of 89,203 nodes fall in 50–149
characters — the width of a signature line.

This is why #5 fails: nothing in `emergency_halt!`'s embedded text contains
"runaway", "stop", or "further action".

## Coverage gaps

Indexed extensions (`AstParserService::SUPPORTED_EXTENSIONS`): ruby, typescript,
javascript, python only.

| ext | nodes |
|---|---|
| rb | 49,718 |
| tsx | 18,478 |
| ts | 11,016 |
| (file nodes) | 9,719 |
| js / mjs / cjs / rake | 272 |

- **Go is absent — doubly.** The parser has no Go support, *and* `find /opt/powernode -name '*.go'` returns **0** on ops-hub: the agent source is not deployed there (it ships as a binary in `powernode-system-base`). The entire on-node agent — boot slots, module composition, unit generation, fsverity — is undiscoverable.
- No `.sh`, `.yaml`, `.md`. Module manifests and runbooks are invisible to code search.
- **19,986 `constant` nodes** (22% of the index) compete for top-k slots against methods and classes.

## Score separation

Exact-name hits top out ~0.60; behavioural misses land 0.42–0.52. The bands
overlap, so **an agent cannot distinguish "found it" from "found something
adjacent"** by score. Probe 5 returned three confident-looking, wholly wrong
results at 0.49–0.52 — the failure mode is silent and plausible, which is worse
for an autonomous caller than an empty result.

## Recommendations (not implemented — audit only)

1. **Embed real semantics.** Include the leading comment/docstring and a
   signature-plus-body summary in `description`. This is the single highest-value
   change; everything else is secondary. Requires a re-vector (cheap now that
   embedding is batched — ~13 min for the full index).
2. **Add Go to `SUPPORTED_EXTENSIONS`**, and index from a checkout that actually
   contains `extensions/system/agent/` (dev-cell has it; ops-hub does not).
3. **Down-weight or exclude bare `constant` nodes** from default results.
4. **Return a calibrated confidence** (or suppress sub-threshold results) so a
   caller can tell a real hit from noise.

Until (1) lands, agents should treat `code_semantic_search` as a **symbol-name
search**: query with likely identifier vocabulary ("kill switch", "instance pool
reaper"), not with behavioural descriptions, and fall back to
`code_identifier_search` / grep when the name is unknown.

---

## Round 2 — measured outcome of (1) and the dilution fix (2026-08-03)

Both recommendations were implemented and the index fully re-vectored
(89,216/89,216 embedded):

- **v37** — `AstParserService` extracts doc comments (ruby `#`, ts/js `//` and
  `/** */`, python docstrings); `build_description` appends them.
- **v38** — embedded text separated from the display description.
  `embedding_text` contributes the identifier, a word-split form, the owning
  class and the doc — dropping the twice-repeated file path, kind, visibility
  and parameter names.

Doc coverage achieved: **34,578 / 89,216 nodes (38.8%)**.

| Query | Baseline | After v38 |
|---|---|---|
| "kill switch emergency halt" (identifier) | 0.603, correct top-3 | **0.731**, correct top-3, **plus a frontend `useEmergencyHalt` hit at 0.698** |
| "immediately stop a runaway autonomous agent…" (behavioural) | miss, top 0.519 | **still miss**, top 0.559 — target not in top-**10** |
| "let internal service-to-service calls bypass…" (behavioural) | miss, top 0.436 | **still miss**, top 0.497, results now topically closer (`authenticate_service_request`) |

**Verdict: identifier retrieval improved substantially (+21% similarity, and
cross-language results now surface). Behavioural retrieval did NOT become
reliable.** Nothing regressed.

**Why it did not close.** `emergency_halt!` has its doc, its parent and a fresh
vector, and still loses to `demote_all_agents_to_supervised` — which has **no
doc at all** — because that identifier's own words ("demote all agents") match
the query's vocabulary. All candidates cluster in a narrow 0.51–0.56 band, well
below the 0.73 an identifier match reaches. Two structural reasons:

1. **61% of nodes still have no behavioural text**, and a well-named
   undocumented symbol legitimately outranks a documented one.
2. Corpus entries are terse fragments (identifier + a one-line doc). A
   general-purpose embedding model does not place a long natural-language
   question and a short code-symbol fragment close together, whatever the
   fragment contains.

**Stopping here** per the Stop & Ask rule — three attempts at the same goal.
Options beyond this point, in rough order of expected effect, none attempted:

1. **LLM-generated natural-language summaries per symbol** — makes the corpus
   the same *kind* of text as the query. Expensive; the only option that
   plausibly closes the gap outright.
2. **Hybrid retrieval** — rank-fuse vector similarity with the existing
   `code_identifier_search` (keyword/BM25). Cheap, and directly targets the
   observed failure, since the right answer is usually retrievable lexically.
3. **Include a body snippet**, not just the doc, for undocumented symbols.

---

## Round 3 — hybrid retrieval (v39/v40, 2026-08-03)

`code_semantic_search` now fuses vector similarity with a term-based lexical
arm using Reciprocal Rank Fusion. The lexical arm could not reuse
`code_identifier_search`, which matches the whole query as one ILIKE substring —
a behavioural sentence matches no identifier, so it would have contributed
nothing. Terms are weighted `log((N+1)/(df+1)) + 1` and damped by description
length; a first live run without those two corrections ranked a verbose executor
above the right answer purely on word volume.

| Query | Before hybrid | After |
|---|---|---|
| "kill switch emergency halt" (identifier) | 0.731, correct | **unchanged, now `matched_by: [vector, lexical]` on all top-3** |
| "halt all agentic activity and snapshot state before stopping" (behavioural) | — | **top-3 all kill-switch subsystem, all both-arm**: `halted?`, `kill_switch_engaged?` (extension), `capture_state_snapshot` |
| "immediately stop a runaway autonomous agent…" (behavioural) | miss | **still miss** |

**The boundary is now well defined.** A behavioural query succeeds when it shares
**any distinctive vocabulary** with the target. It fails when it does not:
`emergency_halt!` reads "Coordinated emergency stop — halts ALL agentic
activity", while the failing query says "immediately stop a runaway autonomous
agent from taking any further action". The only shared words are "stop" and
"agent" — one common, one ubiquitous in this codebase. The distinctive terms
("runaway", "immediately", "autonomous") appear nowhere in the target, so the
lexical arm cannot reach it and the embedding model does not bridge it either.
**No retrieval method spans genuinely disjoint vocabulary**; that needs the
corpus rewritten into query-like language (LLM summaries), not better ranking.

Two secondary wins worth keeping:

- `matched_by` (vector / lexical / both) plus per-arm ranks are returned, so a
  caller can distinguish a meaning match from a word match. Agreement across
  both arms is a far better confidence signal than the old flat similarity,
  which never separated hits from noise.
- With embeddings down the tool degrades to `lexical_only` instead of failing
  the query outright.

Caveat observed in practice: comments that *discuss* retrieval now rank for
retrieval queries — `IndexingService#build_description` surfaces for "stop a
runaway agent" because its comment quotes that phrase. Correct behaviour, but a
reminder that prose in comments is indexed as evidence.

Operational note: bulk embedding remains fragile. The re-vector failed twice
mid-run (`Worker embedding service returned no results for batch`, and a
wholesale stall after ~18.4k nodes) and needed a paced, retrying backfill with
an id cursor to finish. Always verify `count(embedding) = count(id)` afterwards.
Re-vectoring also requires a **walk first** — `properties.doc`/`parent` are
written by `upsert_node`, so an embed-only pass over nodes indexed by older code
silently produces identifier-only vectors.

Related: [[code-reindex-never-reembeds-existing-nodes]] in auto-memory for the
indexing mechanics and re-vector procedure.
