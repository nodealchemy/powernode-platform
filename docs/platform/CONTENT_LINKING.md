# Content Linking (Wikilinks + Backlinks)

**Wikilink extraction, backlink indexing, and page embeddings on the knowledge graph**

**Version**: 0.9 (implementation in progress) | **Last Updated**: April 2026

---

## Overview

Content Linking extends the platform's `Page` and `KnowledgeBase::Article` models with bidirectional linking on the knowledge graph. Authors reference other content with Obsidian-style wikilinks — `[[Title]]` or `[[Title|Display Text]]` — and the backend extracts those references into typed `references` edges on `Ai::KnowledgeGraphEdge`. Each referenced page can then render its inbound-link panel (backlinks), unlinked plain-text mentions, and semantically related pages (based on embeddings).

The design goal is to give long-form content the same knowledge-graph surface area as structured entities, so pages, KB articles, missions, and agents all coexist as linkable nodes in one graph.

> **Implementation status:** The backend service (`ContentLinkService`) is in place with full logic for extraction, backlinks, unlinked mentions, and page embeddings. The frontend `BacklinksPanel` is also written. The HTTP API routes and `pagesApi` client methods wiring the two together are **still pending** as of April 2026. Expect `pagesApi.getBacklinks / getUnlinkedMentions / getRelatedPages` and corresponding controller actions to land alongside the first shipped version.

---

## Wikilink Syntax

Inside `Page#content` (Markdown):

- `[[Feature Development Guide]]` — resolves to the `Page` or `KnowledgeBase::Article` with a matching title
- `[[Feature Development Guide|see the guide]]` — same resolution, custom display text
- Matching is case-insensitive on title, or exact match on a slug derived by `downcase.gsub(/[^a-z0-9\s-]/, "").gsub(/\s+/, "-")`

**Resolution order:**

1. `Page` scoped to the source page's `account` (account-scoped)
2. `KnowledgeBase::Article` (not account-scoped)

Wikilinks that resolve to nothing are silently dropped from the edge set.

---

## Backend Service

`ContentLinkService` (`server/app/services/content_link_service.rb`)

```ruby
service = ContentLinkService.new(account: account)

# 1. Extract wikilinks + persist as KG edges (idempotent per source node)
service.extract_links!(page)
# => Integer count of edges created

# 2. Fetch inbound links for display in a "Backlinks" UI
service.backlinks_for(page)
# => Array of Page | KnowledgeBase::Article records that reference this page

# 3. Detect unlinked mentions (pages that mention the title as plain text)
service.unlinked_mentions_for(page)
# => ActiveRecord::Relation of Page records (account-scoped, excludes source, excludes pages that already [[wikilink]] it, ordered by updated_at DESC, limit 20)

# 4. Ensure a KG node exists for a page (auto-created if missing)
service.find_or_create_page_node(page)
# => Ai::KnowledgeGraphNode (entity_type "page")

# 5. Generate + store an embedding for the page's content on its KG node
service.generate_page_embedding!(page)
# => vector stored via Ai::KnowledgeGraphNode#set_embedding!
```

### Edge model

```ruby
Ai::KnowledgeGraphEdge.create!(
  account: account,
  source_node: source_page_node,
  target_node: target_content_node,
  relation_type: "references",    # always "references" for wikilinks
  weight: 1.0,
  confidence: 1.0,
  bidirectional: false,
  metadata: { link_text: "[[Original Link Text]]" }
)
```

On re-extraction, `extract_links!` first deletes all outgoing `references` edges from the source node so the set stays canonical for the current content.

### Node model

Pages and articles get KG nodes with:

- `node_type: "entity"`
- `entity_type: "page"` or `"article"`
- `metadata: { content_type: "page" | "article", content_id: <uuid>, slug: <slug> }`

Nodes track `mention_count`, `status: "active"`, `confidence: 1.0` at creation. The content node's name is kept in sync with the page title when `find_or_create_page_node` sees a mismatch.

---

## Expected HTTP API *(not yet wired)*

When the routes land, they're expected to look like:

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/v1/admin/pages/:id/backlinks` | Pages/articles that `[[link]]` to this page |
| `GET` | `/api/v1/admin/pages/:id/unlinked_mentions` | Pages that mention title in plain text only |
| `GET` | `/api/v1/admin/pages/:id/related_pages` | Semantic neighbours via embedding similarity |
| `POST` | `/api/v1/admin/pages/:id/extract_links` | Force re-extraction of wikilinks for this page |
| `POST` | `/api/v1/admin/pages/:id/generate_embedding` | Force regeneration of the page's embedding |

Expected response shape for each read endpoint:

```json
{
  "success": true,
  "data": {
    "backlinks": [
      { "id": "uuid", "title": "...", "slug": "...", "type": "page", "excerpt": "..." }
    ]
  }
}
```

(Shape matches `BacklinkItem` / `UnlinkedMentionItem` / `RelatedPageItem` interfaces consumed by `BacklinksPanel`.)

---

## Frontend Component

`BacklinksPanel` (`frontend/src/features/content/pages/components/BacklinksPanel.tsx`)

Three sections:

1. **Backlinks** — pages that `[[link]]` to the current page
2. **Unlinked Mentions** — pages that mention the title as plain text only, with a "Copy [[link]]" button per row to help authors backfill wikilinks
3. **Related Pages** — semantic neighbours (embedding cosine similarity) with a visual similarity bar

Each list item deep-links to `/app/content/pages/<slug>`.

The panel calls three methods on `pagesApi` (not yet implemented on the client side as of April 2026):

```ts
pagesApi.getBacklinks(pageId)
pagesApi.getUnlinkedMentions(pageId)
pagesApi.getRelatedPages(pageId)
```

Implementing these is the remaining work required to ship the feature.

---

## Integration Points

- **Daily Summaries** (see [DAILY_SUMMARIES.md](DAILY_SUMMARIES.md)) — each summary is a `Page`, so wikilinks in a summary surface as backlinks on the referenced pages. This makes the daily report implicitly traversable through the graph.
- **RAG** — page embeddings produced by `generate_page_embedding!` feed the same retrieval pipeline used by the document search and knowledge-base RAG flows.
- **Knowledge graph tooling** — all `references` edges show up under `platform.search_knowledge_graph` / `platform.get_graph_neighbors` when filtered on `relation_type: "references"`.

---

## Key Files

| Role | Path |
|------|------|
| Service | `server/app/services/content_link_service.rb` |
| KG node model | `server/app/models/ai/knowledge_graph_node.rb` |
| KG edge model | `server/app/models/ai/knowledge_graph_edge.rb` |
| Embedding service | `server/app/services/ai/memory/embedding_service.rb` |
| Frontend panel | `frontend/src/features/content/pages/components/BacklinksPanel.tsx` |
| Frontend API client | `frontend/src/features/content/pages/services/pagesApi.ts` |

## See Also

- [AI_ORCHESTRATION_GUIDE.md](AI_ORCHESTRATION_GUIDE.md) — Core AI platform architecture
- [RAG_SYSTEM_GUIDE.md](RAG_SYSTEM_GUIDE.md) — Retrieval pipeline that consumes these embeddings
- [DAILY_SUMMARIES.md](DAILY_SUMMARIES.md) — Summaries are persisted as Pages and benefit from wikilinks
