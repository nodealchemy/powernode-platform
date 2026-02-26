# RAG System Guide

**Knowledge bases, document processing, hybrid search, and agentic retrieval**

**Version**: 1.0 | **Last Updated**: February 2026

---

## Overview

The RAG (Retrieval-Augmented Generation) system provides document ingestion, chunking, embedding, and multi-modal retrieval for AI agents. It supports vector search, keyword search, graph-based retrieval, and agentic iterative search with automatic query reformulation.

### Key Components

| Component | Purpose |
|-----------|---------|
| `Ai::KnowledgeBase` | Container for documents with embedding configuration |
| `Ai::Document` | Source documents with processing lifecycle |
| `Ai::DocumentChunk` | Chunked document segments with pgvector embeddings |
| `Ai::RagQuery` | Query records with embedding and retrieval metadata |
| `Ai::HybridSearchResult` | Search result records across multiple modes |
| `HybridSearchService` | Multi-modal search with result fusion |
| `GraphRagService` | Graph-based retrieval using knowledge graph communities |
| `AgenticRagService` | Iterative retrieval with LLM-driven query reformulation |

---

## Models

### Ai::KnowledgeBase

Container for documents with configurable embedding and chunking settings.

```ruby
belongs_to :account
belongs_to :created_by, class_name: "User"
has_many :documents, dependent: :destroy
has_many :document_chunks
has_many :rag_queries
has_many :data_connectors
has_many :knowledge_graph_nodes
```

**Configuration fields:**
- `embedding_model` — model used for embeddings (e.g., `text-embedding-3-small`)
- `embedding_provider` — provider for embeddings (e.g., `openai`)
- `chunking_strategy` — how documents are split (e.g., `recursive`, `semantic`)
- `chunk_size` — target chunk size in characters
- `chunk_overlap` — overlap between adjacent chunks

**Lifecycle:** `active` → `indexing` → `active` | `paused` | `error` | `archived`

**Key methods:**
- `start_indexing!` / `complete_indexing!` / `pause!` / `archive!` / `mark_error!`
- `update_stats!` — recalculates document/chunk counts
- `record_query!` — logs a RAG query for analytics

### Ai::Document

Source documents within a knowledge base.

```ruby
belongs_to :knowledge_base
belongs_to :uploaded_by, class_name: "User"
has_many :chunks, class_name: "Ai::DocumentChunk", dependent: :destroy
```

**Lifecycle:** `pending` → `processing` → `indexed` | `failed`

**Key methods:**
- `start_processing!` / `complete_indexing!` / `mark_failed!` / `archive!`
- `refresh!` — re-processes document if content has changed
- `content_changed?` — compares current content against stored checksum
- `generate_checksum` — SHA256 checksum of content

### Ai::DocumentChunk

Individual segments of a document with pgvector embeddings.

```ruby
has_neighbors :embedding  # pgvector cosine distance

belongs_to :document
belongs_to :knowledge_base
```

**Key methods:**
- `set_embedding!(vector)` — stores embedding vector
- `embedded?` — checks if embedding exists
- `similarity_with(other_chunk)` — cosine similarity between two chunks
- `preview` — returns truncated content for display

---

## Search Modes

### HybridSearchService

Combines multiple search strategies with result fusion.

```ruby
service = Ai::Rag::HybridSearchService.new(account: account)

results = service.search(
  query,
  mode: :hybrid,        # :vector, :keyword, :graph, :hybrid
  top_k: 10,
  knowledge_base_ids: [kb.id],
  rerank: true
)
```

**Search modes:**

| Mode | Description | Best For |
|------|-------------|----------|
| `:vector` | Semantic similarity via pgvector embeddings | Meaning-based queries |
| `:keyword` | Full-text search using PostgreSQL | Exact term matching |
| `:graph` | Knowledge graph traversal via GraphRagService | Entity relationship queries |
| `:hybrid` | Combines vector + keyword with fusion | General-purpose retrieval |

**Fusion methods:**
- **Reciprocal Rank Fusion (RRF)** — default; combines rankings using `1/(k + rank)` formula with k=60
- **Weighted Fusion** — weighted combination of normalized scores

### GraphRagService

Graph-based retrieval using knowledge graph communities.

```ruby
service = Ai::Rag::GraphRagService.new(account: account)

results = service.retrieve(query, top_k: 10, max_hops: 2, include_summaries: true)
context = service.build_context(query, token_budget: 4000, max_hops: 3)
```

**Pipeline:**
1. **Seed node discovery** — finds relevant knowledge graph nodes via embedding similarity
2. **Community detection** — discovers connected communities within max hops
3. **Chunk collection** — gathers document chunks linked to community nodes
4. **Scoring** — ranks results by relevance
5. **Summary building** — generates community summaries for context

**Constants:**
- `MAX_SEED_NODES = 5`
- `SEED_DISTANCE_THRESHOLD = 0.8`
- `MAX_COMMUNITIES = 10`
- `COMMUNITY_MIN_SIZE = 3`

### AgenticRagService

Iterative retrieval with LLM-driven query reformulation for complex queries.

```ruby
service = Ai::Rag::AgenticRagService.new(account: account)

result = service.retrieve(query, max_rounds: 3)
# => { answer: "...", sources: [...], rounds: 2, total_results: 15 }
```

**Pipeline per round:**
1. **Search** — runs hybrid search
2. **Rerank** — re-scores results for relevance
3. **Sufficiency check** — enough relevant results? (`MIN_RELEVANT_RESULTS = 3`, `MIN_AVG_SCORE = 0.5`)
4. **Gap identification** — what's missing from the results?
5. **Query reformulation** — LLM rewrites query to fill gaps
6. **Synthesis** — LLM generates answer from accumulated results

**Max rounds:** 3 (configurable via `MAX_ROUNDS`)

---

## Document Processing Pipeline

```
Upload Document
    │
    ▼
┌──────────────────┐
│ Document.create  │  status: pending
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ start_processing │  status: processing
│ Chunking         │  Split into DocumentChunks
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Embedding        │  Generate vectors via embedding model
│ set_embedding!   │  Store in pgvector column
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ complete_indexing │  status: indexed
│ update_stats!    │  Update KB statistics
└──────────────────┘
```

**Chunking strategies:**
- `recursive` — recursive character splitting with overlap
- `semantic` — semantic boundary detection
- Configurable via `chunk_size` and `chunk_overlap` on KnowledgeBase

---

## Query & Analytics

### Ai::RagQuery

Records every RAG query for analytics and quality improvement.

```ruby
has_neighbors :query_embedding

belongs_to :knowledge_base
belongs_to :user
```

**Fields:** `query_text`, `status`, `retrieval_strategy`, `top_k`, `similarity_threshold`, `results_count`, `avg_score`, `processing_time_ms`

**Key methods:**
- `quality_score` — computed quality metric for the query result

### Ai::HybridSearchResult

Records search results with mode and fusion metadata.

```ruby
SEARCH_MODES = %w[vector keyword graph hybrid]
FUSION_METHODS = %w[rrf weighted simple]
```

**Class methods:**
- `avg_latency_for(mode)` — average latency by search mode for optimization

---

## API Endpoints

RAG operations are exposed through the AI controllers:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/ai/rag/query` | Query a knowledge base |
| `GET` | `/api/v1/ai/rag/search` | Search documents |
| `POST` | `/api/v1/ai/rag/knowledge_bases` | Create knowledge base |
| `POST` | `/api/v1/ai/rag/documents` | Upload document |
| `POST` | `/api/v1/ai/rag/documents/:id/process` | Trigger processing |

MCP tools also expose RAG operations:
- `platform.query_knowledge_base` — RAG retrieval query
- `platform.search_documents` — document chunk search
- `platform.add_document` / `platform.process_document` — document management

---

## Key Files

| File | Path |
|------|------|
| Knowledge Base Model | `server/app/models/ai/knowledge_base.rb` |
| Document Model | `server/app/models/ai/document.rb` |
| Document Chunk Model | `server/app/models/ai/document_chunk.rb` |
| RAG Query Model | `server/app/models/ai/rag_query.rb` |
| Hybrid Search Result Model | `server/app/models/ai/hybrid_search_result.rb` |
| Hybrid Search Service | `server/app/services/ai/rag/hybrid_search_service.rb` |
| Graph RAG Service | `server/app/services/ai/rag/graph_rag_service.rb` |
| Agentic RAG Service | `server/app/services/ai/rag/agentic_rag_service.rb` |
| Reranking Service | `server/app/services/ai/rag/reranking_service.rb` |
| RAG Service (core) | `server/app/services/ai/rag_service.rb` |
| RAG Controller | `server/app/controllers/api/v1/ai/rag_controller.rb` |
