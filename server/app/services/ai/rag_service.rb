# frozen_string_literal: true

module Ai
  class RagServiceError < StandardError; end

  class RagService
    attr_reader :account

    def initialize(account)
      @account = account
    end

    # ============================================================================
    # KNOWLEDGE BASE OPERATIONS
    # ============================================================================

    def list_knowledge_bases(filters = {})
      bases = account.ai_knowledge_bases
      bases = bases.where(status: filters[:status]) if filters[:status].present?
      bases = bases.where(is_public: filters[:is_public]) if filters[:is_public].present?
      bases = bases.order(created_at: :desc)
      bases = bases.page(filters[:page]).per(filters[:per_page]) if filters[:page].present?
      bases
    end

    def get_knowledge_base(id)
      account.ai_knowledge_bases.find(id)
    end

    def create_knowledge_base(params, user: nil)
      account.ai_knowledge_bases.create!(
        name: params[:name],
        description: params[:description],
        embedding_model: params[:embedding_model] || "text-embedding-3-small",
        embedding_provider: params[:embedding_provider] || "openai",
        embedding_dimensions: params[:embedding_dimensions] || 1536,
        chunking_strategy: params[:chunking_strategy] || "recursive",
        chunk_size: params[:chunk_size] || 1000,
        chunk_overlap: params[:chunk_overlap] || 200,
        metadata_schema: params[:metadata_schema] || {},
        settings: params[:settings] || {},
        is_public: params[:is_public] || false,
        created_by: user
      )
    end

    def update_knowledge_base(id, params)
      kb = get_knowledge_base(id)
      kb.update!(params.slice(
        :name, :description, :embedding_model, :embedding_provider,
        :chunking_strategy, :chunk_size, :chunk_overlap,
        :metadata_schema, :settings, :is_public
      ))
      kb
    end

    def delete_knowledge_base(id)
      kb = get_knowledge_base(id)
      kb.destroy!
    end

    # ============================================================================
    # DOCUMENT OPERATIONS
    # ============================================================================

    def list_documents(knowledge_base_id, filters = {})
      kb = get_knowledge_base(knowledge_base_id)
      docs = kb.documents
      docs = docs.where(status: filters[:status]) if filters[:status].present?
      docs = docs.where(source_type: filters[:source_type]) if filters[:source_type].present?
      docs = docs.order(created_at: :desc)
      docs = docs.page(filters[:page]).per(filters[:per_page]) if filters[:page].present?
      docs
    end

    def get_document(knowledge_base_id, document_id)
      kb = get_knowledge_base(knowledge_base_id)
      kb.documents.find(document_id)
    end

    def create_document(knowledge_base_id, params, user: nil)
      kb = get_knowledge_base(knowledge_base_id)

      doc = kb.documents.create!(
        name: params[:name],
        source_type: params[:source_type],
        source_url: params[:source_url],
        content_type: params[:content_type],
        content: params[:content],
        content_size_bytes: params[:content]&.bytesize,
        metadata: params[:metadata] || {},
        extraction_config: params[:extraction_config] || {},
        expires_at: params[:expires_at],
        uploaded_by: user
      )

      # Calculate checksum if content provided
      doc.update!(checksum: doc.generate_checksum) if params[:content].present?

      doc
    end

    def process_document(knowledge_base_id, document_id)
      doc = get_document(knowledge_base_id, document_id)
      doc.start_processing!

      kb = doc.knowledge_base
      chunks = chunk_content(doc.content, kb.chunking_strategy, kb.chunk_size, kb.chunk_overlap)

      created_chunks = chunks.each_with_index.map do |chunk_content, idx|
        Ai::DocumentChunk.create!(
          document: doc,
          knowledge_base: kb,
          sequence_number: idx + 1,
          content: chunk_content,
          token_count: estimate_tokens(chunk_content),
          start_offset: 0, # Would need proper offset tracking
          end_offset: chunk_content.length
        )
      end

      doc.complete_indexing!(
        chunk_count: created_chunks.size,
        token_count: created_chunks.sum(&:token_count)
      )

      kb.update_stats!
      doc
    end

    def delete_document(knowledge_base_id, document_id)
      doc = get_document(knowledge_base_id, document_id)
      kb = doc.knowledge_base
      doc.destroy!
      kb.update_stats!
    end

    # ============================================================================
    # EMBEDDING OPERATIONS
    # ============================================================================

    def embed_chunks(knowledge_base_id, document_id: nil)
      kb = get_knowledge_base(knowledge_base_id)
      chunks = kb.document_chunks.without_embeddings
      chunks = chunks.where(document_id: document_id) if document_id.present?

      embedded_count = 0
      chunks.find_each do |chunk|
        embedding = generate_embedding(chunk.content, kb.embedding_model, kb.embedding_provider)
        chunk.set_embedding!(embedding, kb.embedding_model)
        embedded_count += 1
      end

      kb.complete_indexing!
      { embedded_count: embedded_count }
    end

    # ============================================================================
    # QUERY OPERATIONS
    # ============================================================================

    def query(knowledge_base_id, params, user: nil)
      kb = get_knowledge_base(knowledge_base_id)

      # Delegate to hybrid search if mode specified
      search_mode = params[:search_mode]&.to_s
      if search_mode.present? && %w[hybrid graph keyword].include?(search_mode)
        return hybrid_query(kb, params, user: user)
      end

      start_time = Time.current

      # Create query record
      rag_query = Ai::RagQuery.create!(
        account: account,
        knowledge_base: kb,
        user: user,
        query_text: params[:query],
        retrieval_strategy: params[:strategy] || "similarity",
        top_k: params[:top_k] || 5,
        similarity_threshold: params[:threshold] || 0.7,
        filters: params[:filters] || {},
        workflow_run_id: params[:workflow_run_id],
        agent_execution_id: params[:agent_execution_id]
      )

      rag_query.start_processing!

      # Generate query embedding
      query_embedding = generate_embedding(params[:query], kb.embedding_model, kb.embedding_provider)
      rag_query.set_embedding!(query_embedding)

      # Retrieve relevant chunks
      chunks = retrieve_chunks(
        kb,
        query_embedding,
        top_k: rag_query.top_k,
        threshold: rag_query.similarity_threshold,
        filters: rag_query.filters
      )

      # Complete query
      latency = ((Time.current - start_time) * 1000).round(2)
      rag_query.complete!(chunks: chunks, latency_ms: latency)

      kb.record_query!

      {
        query_id: rag_query.id,
        query: params[:query],
        chunks: chunks,
        total_retrieved: chunks.size,
        latency_ms: latency
      }
    end

    def get_query_history(knowledge_base_id, filters = {})
      kb = get_knowledge_base(knowledge_base_id)
      queries = kb.rag_queries.recent
      queries = queries.where(status: filters[:status]) if filters[:status].present?
      queries = queries.page(filters[:page]).per(filters[:per_page]) if filters[:page].present?
      queries
    end

    # ============================================================================
    # DATA CONNECTOR OPERATIONS
    # ============================================================================

    def list_connectors(knowledge_base_id)
      kb = get_knowledge_base(knowledge_base_id)
      kb.data_connectors.order(created_at: :desc)
    end

    def create_connector(knowledge_base_id, params, user: nil)
      kb = get_knowledge_base(knowledge_base_id)

      kb.data_connectors.create!(
        account: account,
        name: params[:name],
        connector_type: params[:connector_type],
        connection_config: params[:connection_config] || {},
        sync_config: params[:sync_config] || {},
        sync_frequency: params[:sync_frequency],
        created_by: user
      )
    end

    def sync_connector(knowledge_base_id, connector_id)
      kb = get_knowledge_base(knowledge_base_id)
      connector = kb.data_connectors.find(connector_id)

      # Placeholder for actual sync logic based on connector type
      result = perform_sync(connector)
      connector.record_sync!(result)

      result
    end

    # ============================================================================
    # ANALYTICS
    # ============================================================================

    def get_analytics(knowledge_base_id, period_days: 30)
      kb = get_knowledge_base(knowledge_base_id)
      start_date = period_days.days.ago

      queries = kb.rag_queries.where("created_at >= ?", start_date)

      {
        total_queries: queries.count,
        successful_queries: queries.completed.count,
        failed_queries: queries.failed.count,
        avg_latency_ms: queries.completed.average(:query_latency_ms)&.round(2),
        avg_chunks_retrieved: queries.completed.average(:chunks_retrieved)&.round(2),
        avg_similarity_score: queries.completed.average(:avg_similarity_score)&.round(4),
        document_count: kb.document_count,
        chunk_count: kb.chunk_count,
        total_tokens: kb.total_tokens,
        storage_bytes: kb.storage_bytes,
        queries_by_day: queries.group_by_day(:created_at).count
      }
    end

    private

    def hybrid_query(kb, params, user: nil)
      hybrid_service = Ai::Rag::HybridSearchService.new(account)

      result = hybrid_service.search(
        query: params[:query],
        mode: params[:search_mode] || :hybrid,
        top_k: params[:top_k] || 10,
        knowledge_base_id: kb.id
      )

      # Optionally rerank
      if params[:enable_reranking]
        reranking_service = Ai::Rag::RerankingService.new(account)
        result[:results] = reranking_service.rerank(
          query: params[:query],
          results: result[:results]
        )
      end

      kb.record_query!

      {
        query: params[:query],
        search_mode: params[:search_mode],
        results: result[:results],
        total_retrieved: result[:results].size,
        metadata: result[:metadata]
      }
    end

    def chunk_content(content, strategy, chunk_size, overlap)
      return [] if content.blank?

      case strategy
      when "fixed"
        fixed_chunking(content, chunk_size, overlap)
      when "sentence"
        sentence_chunking(content, chunk_size, overlap)
      when "paragraph"
        paragraph_chunking(content)
      else # recursive
        recursive_chunking(content, chunk_size, overlap)
      end
    end

    def fixed_chunking(content, size, overlap)
      chunks = []
      start_idx = 0

      while start_idx < content.length
        chunk = content[start_idx, size]
        chunks << chunk
        start_idx += (size - overlap)
      end

      chunks
    end

    def sentence_chunking(content, max_size, _overlap)
      sentences = content.split(/(?<=[.!?])\s+/)
      chunks = []
      current_chunk = ""

      sentences.each do |sentence|
        if (current_chunk.length + sentence.length) <= max_size
          current_chunk += " " + sentence
        else
          chunks << current_chunk.strip unless current_chunk.blank?
          current_chunk = sentence
        end
      end

      chunks << current_chunk.strip unless current_chunk.blank?
      chunks
    end

    def paragraph_chunking(content)
      content.split(/\n\n+/).reject(&:blank?)
    end

    def recursive_chunking(content, size, overlap)
      # Split by paragraphs first, then sentences, then fixed if needed
      paragraphs = paragraph_chunking(content)

      chunks = []
      paragraphs.each do |para|
        if para.length <= size
          chunks << para
        else
          chunks.concat(sentence_chunking(para, size, overlap))
        end
      end

      chunks
    end

    def estimate_tokens(text)
      # Rough estimation: ~4 characters per token
      (text.length / 4.0).ceil
    end

    def generate_embedding(text, model, provider)
      embedding_service = Ai::EmbeddingService.new(account: account)

      begin
        result = embedding_service.generate(
          text: text,
          model: model,
          provider: provider
        )
        result[:embedding]
      rescue Ai::EmbeddingService::EmbeddingError => e
        Rails.logger.error "[RagService] Embedding generation failed: #{e.message}"
        raise Ai::RagServiceError, "Failed to generate embedding: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "[RagService] Unexpected error generating embedding: #{e.message}"
        raise Ai::RagServiceError, "Embedding service unavailable. Please configure an embedding provider."
      end
    end

    def retrieve_chunks(knowledge_base, query_embedding, top_k:, threshold:, filters:)
      chunks = knowledge_base.document_chunks.with_embeddings

      # Calculate similarities (in production, use vector DB)
      results = chunks.map do |chunk|
        score = chunk.similarity_with(query_embedding)
        next if score < threshold

        {
          chunk_id: chunk.id,
          document_id: chunk.document_id,
          content: chunk.content,
          score: score.round(4),
          metadata: chunk.metadata
        }
      end.compact

      # Sort by score and limit
      results.sort_by { |r| -r[:score] }.first(top_k)
    end

    def perform_sync(connector)
      # Placeholder for actual sync implementations
      {
        success: true,
        documents_count: 0,
        message: "Sync completed for #{connector.connector_type}"
      }
    end
  end
end
