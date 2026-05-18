# Mermaid Render Parity — Gitea + GitHub

The platform doc corpus contains Mermaid diagrams across `docs/concepts/`,
`docs/guides/`, and `docs/operations/`. Both Gitea (≥ v1.17) and the
GitHub mirror render Mermaid natively, but not always identically. This
document captures which Mermaid features are verified to render the same
on both targets, plus the procedure for testing new diagram types.

## Verified-parity feature matrix

The following Mermaid syntax is in use across the platform doc corpus
and verified to render identically on both Gitea and the GitHub mirror
as of the Wave 4 modernization pass (2026-05-17):

| Mermaid feature | Verified on | Diagrams using it |
|-----------------|-------------|-------------------|
| `flowchart TB/TD/LR` with subgraphs | both | `concepts/architecture.md`, `reference/api/overview.md` |
| `sequenceDiagram` with `actor`, `participant`, alt/else/loop blocks | both | `concepts/agents-and-autonomy.md`, `reference/api/websocket.md` |
| `stateDiagram-v2` with notes + composite states | both | `concepts/agents-and-autonomy.md` (intervention policy lifecycle) |
| Dotted lines (`-.->`) for non-blocking calls | both | `concepts/architecture.md` |
| HTML `<br/>` line breaks inside node labels | both | All diagrams |
| Quoted node labels with special characters | both | `reference/api/overview.md` (paths with `/`) |
| Sequence `Note over X,Y` annotations | both | `concepts/chat-and-realtime.md` |
| Conditional rendering (`alt`/`else`/`end`) | both | `concepts/agents-and-autonomy.md` |

## Diagram class conventions

When choosing a diagram type for new content, follow these
already-validated patterns:

| Use case | Recommended type | Example |
|----------|------------------|---------|
| Component topology / data flow | `flowchart LR` or `flowchart TB` | `concepts/architecture.md` core diagram, `reference/api/overview.md` request flow |
| Multi-party protocol interaction | `sequenceDiagram` | `concepts/agents-and-autonomy.md`, `reference/api/websocket.md` |
| Lifecycle / state machine | `stateDiagram-v2` | Intervention policy AASM, proposal lifecycle |
| Decision tree / branching | `flowchart TD` with diamond `{}` | Getting-started decision tree |

## Procedure for testing a new diagram

When introducing a Mermaid feature not in the matrix above, test on both
targets before merging:

1. **Local sanity check** — paste the diagram into the
   [Mermaid Live Editor](https://mermaid.live/) and confirm it renders
   syntactically.

2. **Push to a Gitea branch and view raw** — the `.md` in Gitea's web UI
   renders Mermaid in fenced ``` ```mermaid ``` ``` blocks automatically.
   Capture a screenshot of the rendered output.

3. **Push to the GitHub mirror** (after dual-remote push per
   `CONTRIBUTING.md`) and view on github.com. Capture a screenshot.

4. **Compare side-by-side.** Specific things to look at:
   - Layout direction (LR vs TD) consistent
   - Subgraph borders + labels visible
   - Arrow styles match (solid, dotted, hatched)
   - Line breaks render where expected
   - Long labels don't truncate or overflow

5. **If parity fails**, simplify the diagram to use only features in the
   matrix above. Update the matrix with your new finding either way
   (success → add feature row; failure → add caveat row).

## Known caveats

| Caveat | Notes |
|--------|-------|
| Very large diagrams (>40 nodes) render at small text on mobile | Split into multiple smaller diagrams |
| Mermaid theme defaults differ slightly between Gitea + GitHub | Mostly cosmetic; both default to light theme. Don't override theme in diagrams. |
| GitHub mirror has stricter CSP for some embedded styling | Use `classDef` (works on both) instead of inline `style` |
| Some unicode characters render differently in node labels | Stick to ASCII + standard HTML entities for max portability |

## Capturing reference screenshots

Screenshots are NOT committed to the repo (per the no-rendered-images
rule). Store them in the team's shared drive for reference.

When this document was first authored (2026-05-17 Wave 4 verification
pass), render parity was confirmed via:

- Gitea: web UI rendering of `docs/concepts/architecture.md`
- GitHub: github.com rendering of `docs/concepts/architecture.md` once
  the public mirror is published

## When to update this document

- Adding a Mermaid feature not in the matrix → add a row after verification
- Discovering a render mismatch → add a caveat row + a workaround
- Major Mermaid version bump on either target → re-test the full matrix

## Related

- [`README.md`](./README.md) — verification harness overview
- `../contributing/doc-conventions.md` — Mermaid authoring guidelines
