---
Last Updated: 2026-02-26
Platform Version: 0.2.0
---

# Content Management Guide

Knowledge base articles, content pages, and CMS workflow management within the Powernode platform.

## Overview

Powernode includes two content systems:

1. **Knowledge Base** (8 models in `KnowledgeBase::` namespace) — Rich articles with categories, tags, full-text search, editorial workflows, moderated comments, and view analytics
2. **Pages** — Simple standalone content pages with markdown rendering and SEO metadata

---

## Knowledge Base System

### Models (`server/app/models/knowledge_base/`)

#### KnowledgeBase::Article

Core article model with full-text search, tagging, and view tracking.

**Statuses:** `draft`, `review`, `published`, `archived`

**Key features:**
- PostgreSQL full-text search via `search_vector` with `ts_rank` ordering
- Slug-based URLs with uniqueness enforcement
- Auto-generated excerpts from content
- SEO metadata: `meta_title`, `meta_description`, `meta_keywords`
- View tracking with per-user deduplication (authors excluded)
- View analytics: session tracking, IP, reading time, read-to-end tracking
- Reading time estimation (200 WPM)
- Related article discovery (tag-based + category-based)
- Permission-based access control (`kb.manage`, `kb.update`, `kb.publish`, `kb.moderate`)

**Associations:**
```
Article → Category (KnowledgeBase::Category)
Article → Author (User)
Article → Tags (many-to-many via ArticleTag)
Article → Attachments (many)
Article → Comments (many)
Article → ArticleViews (many)
Article → Workflows (many)
```

**Scopes:**
- `published` — Published articles only
- `public_articles` — Publicly accessible
- `featured` — Featured/pinned articles
- `in_category(id)` — Filter by category
- `by_author(id)` — Filter by author
- `search_by_text(query)` — Full-text search with ranking
- `recent` / `popular` / `ordered` — Sorting

#### KnowledgeBase::Category

Hierarchical categories with `parent_id` for nesting. Includes circular reference prevention to avoid infinite loops in the tree.

#### KnowledgeBase::Tag

Tagging system with slug-based identification.
- Articles linked via `KnowledgeBase::ArticleTag` join table (with auto-increment usage counters)
- Tags auto-created via `tag_names=` setter
- Color support (`#RRGGBB` format) for visual categorization

#### KnowledgeBase::Attachment

File attachments for articles (max 50MB, stored in `public/uploads/kb/`). MIME type detection on upload.

#### KnowledgeBase::Comment

Nested comment system with moderation:
- **Statuses:** `pending`, `approved`, `rejected`, `spam`
- Reply threading via parent_id
- Auto-approval for users with `kb.moderate` permission
- Moderation queue for unprivileged users

#### KnowledgeBase::ArticleView

View tracking with user, session, IP, and user agent recording.

#### KnowledgeBase::Workflow

Content lifecycle workflows for articles.

**Workflow types:** `review`, `approval`, `translation`, `update`
**Statuses:** `pending`, `in_progress`, `completed`, `cancelled`

**Features:**
- Due date tracking with overdue detection
- Duration tracking (time in progress)
- Cancellation with reason recording
- Assigned to specific users

---

## Content Pages

The `Page` model provides simple standalone content pages outside the knowledge base article structure.

**Key features:**
- Title, slug, content fields
- Status: `draft` / `published`
- Markdown-to-HTML rendering via `PageService`
- SEO metadata support
- Public access (no authentication required for published pages)

### Public API
```
GET /api/v1/pages         # List published pages (no auth)
GET /api/v1/pages/:slug   # Show page by slug (no auth)
```

### Admin API
```
GET    /api/v1/admin/pages           # List all pages
POST   /api/v1/admin/pages           # Create page
PUT    /api/v1/admin/pages/:id       # Update page
DELETE /api/v1/admin/pages/:id       # Delete page
POST   /api/v1/admin/pages/:id/publish    # Publish
POST   /api/v1/admin/pages/:id/unpublish  # Unpublish
POST   /api/v1/admin/pages/:id/duplicate  # Duplicate
```
Requires `admin.access` permission.

---

### Frontend Components (`frontend/src/features/content/`)

```
frontend/src/features/content/
├── files/               # File management components
├── knowledge-base/      # KB article components
│   ├── components/     # Article list, detail, editor
│   └── services/       # KB API service layer
├── pages/              # Content page components
│   ├── components/     # Page list, detail, editor
│   └── services/       # Pages API service layer
└── index.ts            # Feature barrel export
```

---

## API Endpoints

### Public Knowledge Base

```
GET    /api/v1/kb/articles          # List published articles (search, filters)
GET    /api/v1/kb/articles/:id      # Show article (records view)
GET    /api/v1/kb/categories        # List categories
GET    /api/v1/kb/categories/tree   # Category tree structure
GET    /api/v1/kb/tags              # List popular tags
GET    /api/v1/kb/comments          # List approved comments
POST   /api/v1/kb/comments          # Create comment (enters moderation)
```

### Admin Knowledge Base

```
POST   /api/v1/kb/articles          # Create article
PUT    /api/v1/kb/articles/:id      # Update article
DELETE /api/v1/kb/articles/:id      # Delete article
```

### MCP Tools

| Tool | Description |
|------|-------------|
| `platform.list_kb_articles` | List articles with pagination and filters |
| `platform.get_kb_article` | Get article content and metadata |
| `platform.create_kb_article` | Create a new article |
| `platform.update_kb_article` | Update an existing article |
| `platform.list_pages` | List content pages |
| `platform.get_page` | Get page content and metadata |
| `platform.create_page` | Create a new page |
| `platform.update_page` | Update an existing page |

---

## Content Workflow

### Article Lifecycle

```
Draft → Review → Published → Archived
  ↑       │          │
  └───────┘          │
  (rejected)    (updated → review)
```

1. **Draft** — Author creates/edits content
2. **Review** — Submitted for peer review via workflow
3. **Published** — Approved and visible (auto-sets `published_at`)
4. **Archived** — Retired from active use

### Workflow Types

| Type | Purpose |
|------|---------|
| `review` | Content review before publishing |
| `approval` | Management approval for sensitive content |
| `translation` | Content translation to other languages |
| `update` | Scheduled content refresh/update |

### Workflow Lifecycle

```
Pending → In Progress → Completed / Cancelled
```

- Workflows assigned to specific users
- Due date tracking with overdue detection
- Duration tracking from start to completion

---

## Search

### Full-Text Search

Articles use PostgreSQL's built-in full-text search:
- `search_vector` column (tsvector) for indexed content
- `plainto_tsquery` for query parsing
- `ts_rank` for relevance scoring
- SQL injection protection via `connection.quote`

### Search Usage

```ruby
# Backend
KnowledgeBase::Article.search_by_text("deployment guide")

# MCP
platform.list_kb_articles(query: "deployment guide")
```

---

## Access Control

### Article Visibility

| User | Can View | Can Edit |
|------|----------|----------|
| Public (unauthenticated) | Published + `is_public` only | No |
| Author | All own articles | Own articles |
| `kb.manage` permission | All articles | All articles |
| `kb.update` permission | Published + own | All articles |

### Permission Matrix

| Permission | Actions |
|-----------|---------|
| `kb.view` | List and view published articles |
| `kb.create` | Create new articles |
| `kb.update` | Edit existing articles |
| `kb.manage` | Full CRUD + workflow management |

---

## Related Systems

### RAG Integration

Knowledge base articles can be ingested into Powernode's RAG system:
- `platform.add_document` — Add article to knowledge base
- `platform.process_document` — Chunk and embed for retrieval
- `platform.query_knowledge_base` — RAG-powered search

### AI Knowledge System

Separate from KB articles, the AI knowledge system (`platform.create_knowledge`, `platform.search_knowledge`) manages operational knowledge used by AI agents and Claude Code sessions. KB articles are user-facing content; AI knowledge entries are agent-facing reference material.
