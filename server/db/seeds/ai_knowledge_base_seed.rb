# frozen_string_literal: true

# Seed the default GLOBAL RAG knowledge base (account_id nil), upserted by
# source_key (= name parameterized) so future seeds update in place. This is
# foundational platform content — no account needed (seeds in core/prod too).
# Idempotent: upserts the KB and its starter document.

# GLOBAL baseline content: account_id nil, source_key upsert.
return unless Powernode::Seeds.baseline?

kb_name = "Platform Documentation"
kb_source_key = kb_name.parameterize

kb = Ai::KnowledgeBase.find_or_initialize_by(source_key: kb_source_key, account_id: nil)
kb.assign_attributes(
  name: kb_name,
  description: "Default knowledge base for platform docs, guides, and reference. Add documents to enable AI search and context retrieval.",
  embedding_model: "text-embedding-3-small",
  embedding_provider: "openai",
  embedding_dimensions: 1536,
  chunking_strategy: "recursive",
  chunk_size: 1000,
  chunk_overlap: 200,
  metadata_schema: {},
  settings: {},
  is_public: true,
  status: "active"
)
kb.save!

# Add (or refresh) the starter document — keyed by name within this KB.
doc = kb.documents.find_or_initialize_by(name: "Getting Started with RAG")
doc.assign_attributes(
  source_type: "upload",
  content_type: "text/markdown",
  content: <<~MARKDOWN,
      # Getting Started with RAG Knowledge Bases

      ## Overview
      RAG (Retrieval-Augmented Generation) knowledge bases let AI agents search and retrieve from your documents, grounding responses in your own data.

      ## How It Works
      1. **Create a Knowledge Base** - Organize documents by topic or domain
      2. **Add Documents** - Upload text, markdown, or other content
      3. **Process Documents** - Automatic chunking splits documents into searchable segments
      4. **Generate Embeddings** - Vector embeddings enable semantic search
      5. **Query** - Agents search for relevant context using hybrid search (semantic + keyword)

      ## Document Types
      - **Text/Markdown** - Documentation, guides, procedures
      - **Code Snippets** - API references, code examples
      - **FAQs** - Frequently asked questions and answers
      - **Policies** - Company policies, compliance documents

      ## Search Modes
      - **Hybrid** (recommended) - Combines vector similarity with keyword matching
      - **Vector** - Pure semantic search using embeddings
      - **Keyword** - Traditional full-text search
      - **Graph** - Knowledge graph-augmented search

      ## Best Practices
      - Keep documents focused on a single topic
      - Use descriptive titles for easy identification
      - Update documents regularly to maintain accuracy
      - Use tags and metadata for better organization
    MARKDOWN
  content_size_bytes: 0,
  status: "pending"
)
doc.save!
doc.update!(content_size_bytes: doc.content.bytesize, checksum: doc.generate_checksum)

kb.update_stats!

Rails.logger.info "[Seed] Upserted GLOBAL RAG knowledge base '#{kb_name}' (source_key=#{kb_source_key})"
puts "  ✅ Global RAG knowledge bases: #{Ai::KnowledgeBase.global.count}"
