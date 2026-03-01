# frozen_string_literal: true

# Seed default RAG knowledge bases for accounts with AI features enabled
# Idempotent: skips if a KB with the same name already exists for the account

Account.find_each do |account|
  # Only seed for accounts that have at least one AI provider configured
  next unless account.ai_providers.active.exists?

  kb_name = "Platform Documentation"
  next if Ai::KnowledgeBase.exists?(account: account, name: kb_name)

  admin_user = account.users.joins(:user_roles, user_roles: :role)
                       .where(roles: { name: "super_admin" })
                       .first || account.users.first

  kb = Ai::KnowledgeBase.create!(
    account: account,
    name: kb_name,
    description: "Default knowledge base for platform documentation, guides, and reference materials. Add documents here to enable AI-powered search and context retrieval.",
    embedding_model: "text-embedding-3-small",
    embedding_provider: "openai",
    embedding_dimensions: 1536,
    chunking_strategy: "recursive",
    chunk_size: 1000,
    chunk_overlap: 200,
    metadata_schema: {},
    settings: {},
    is_public: false,
    status: "active",
    created_by: admin_user
  )

  # Add a starter document
  doc = kb.documents.create!(
    name: "Getting Started with RAG",
    source_type: "upload",
    content_type: "text/markdown",
    content: <<~MARKDOWN,
      # Getting Started with RAG Knowledge Bases

      ## Overview
      RAG (Retrieval-Augmented Generation) knowledge bases allow AI agents to search and retrieve relevant information from your documents. This enhances agent responses with accurate, up-to-date context from your own data.

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
    status: "pending",
    uploaded_by: admin_user
  )
  doc.update!(content_size_bytes: doc.content.bytesize, checksum: doc.generate_checksum)

  kb.update_stats!

  Rails.logger.info "[Seed] Created RAG knowledge base '#{kb_name}' for account #{account.id}"
end
