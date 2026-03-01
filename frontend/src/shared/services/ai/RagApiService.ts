/**
 * RAG API Service - Knowledge-Augmented Agents
 *
 * Handles knowledge bases, documents, embeddings, queries, and data connectors.
 */

import { BaseApiService, QueryFilters } from '@/shared/services/ai/BaseApiService';

// ============================================================================
// Types
// ============================================================================

export interface KnowledgeBase {
  id: string;
  name: string;
  description: string | null;
  status: 'active' | 'indexing' | 'paused' | 'archived' | 'error';
  embedding_model: string;
  embedding_provider: string;
  embedding_dimensions?: number;
  chunking_strategy: string;
  chunk_size: number;
  chunk_overlap: number;
  is_public: boolean;
  document_count: number;
  chunk_count: number;
  total_tokens: number;
  storage_bytes: number;
  last_indexed_at: string | null;
  last_queried_at: string | null;
  metadata_schema?: Record<string, unknown>;
  settings?: Record<string, unknown>;
  created_at: string;
}

export interface Document {
  id: string;
  name: string;
  source_type: 'upload' | 'url' | 'api' | 'database' | 'cloud_storage' | 'git';
  source_url: string | null;
  content_type: string | null;
  status: 'pending' | 'processing' | 'indexed' | 'failed' | 'archived';
  chunk_count: number;
  token_count: number;
  content_size_bytes: number;
  processed_at: string | null;
  metadata?: Record<string, unknown>;
  processing_errors?: Array<{ error: string; timestamp: string }>;
  checksum?: string;
  created_at: string;
}

export interface RagQuery {
  id: string;
  query_text: string;
  retrieval_strategy: string;
  status: 'pending' | 'processing' | 'completed' | 'failed';
  chunks_retrieved: number;
  avg_similarity_score: number | null;
  query_latency_ms: number | null;
  created_at: string;
}

export interface QueryResult {
  query_id: string;
  query: string;
  chunks: RetrievedChunk[];
  total_retrieved: number;
  latency_ms: number;
}

export interface RetrievedChunk {
  chunk_id: string;
  document_id: string;
  content: string;
  score: number;
  metadata: Record<string, unknown>;
}

export interface DataConnector {
  id: string;
  name: string;
  connector_type:
    | 'notion'
    | 'confluence'
    | 'google_drive'
    | 'dropbox'
    | 'github'
    | 's3'
    | 'database'
    | 'api'
    | 'web_scraper';
  status: 'active' | 'paused' | 'error' | 'disconnected';
  sync_frequency: string | null;
  documents_synced: number;
  sync_errors: number;
  last_sync_at: string | null;
  next_sync_at: string | null;
  created_at: string;
}

export interface RagAnalytics {
  total_queries: number;
  successful_queries: number;
  failed_queries: number;
  avg_latency_ms: number | null;
  avg_chunks_retrieved: number | null;
  avg_similarity_score: number | null;
  document_count: number;
  chunk_count: number;
  total_tokens: number;
  storage_bytes: number;
  queries_by_day: Record<string, number>;
}

export interface KnowledgeBaseFilters extends QueryFilters {
  status?: string;
  is_public?: boolean;
}

export interface DocumentFilters extends QueryFilters {
  status?: string;
  source_type?: string;
}

// ============================================================================
// Service
// ============================================================================

class RagApiService extends BaseApiService {
  private basePath = '/ai/rag';

  // Knowledge Bases
  async listKnowledgeBases(filters?: KnowledgeBaseFilters): Promise<{
    knowledge_bases: KnowledgeBase[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}/knowledge_bases${queryString}`);
  }

  async getKnowledgeBase(id: string): Promise<KnowledgeBase> {
    return this.get<KnowledgeBase>(`${this.basePath}/knowledge_bases/${id}`);
  }

  async createKnowledgeBase(data: {
    name: string;
    description?: string;
    embedding_model?: string;
    embedding_provider?: string;
    embedding_dimensions?: number;
    chunking_strategy?: string;
    chunk_size?: number;
    chunk_overlap?: number;
    is_public?: boolean;
    metadata_schema?: Record<string, unknown>;
    settings?: Record<string, unknown>;
  }): Promise<KnowledgeBase> {
    return this.post<KnowledgeBase>(`${this.basePath}/knowledge_bases`, data);
  }

  async updateKnowledgeBase(
    id: string,
    data: Partial<Parameters<typeof this.createKnowledgeBase>[0]>
  ): Promise<KnowledgeBase> {
    return this.patch<KnowledgeBase>(
      `${this.basePath}/knowledge_bases/${id}`,
      data
    );
  }

  async deleteKnowledgeBase(id: string): Promise<{ success: boolean }> {
    return this.delete(`${this.basePath}/knowledge_bases/${id}`);
  }

  // Documents
  async listDocuments(
    knowledgeBaseId: string,
    filters?: DocumentFilters
  ): Promise<{
    documents: Document[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/documents${queryString}`
    );
  }

  async getDocument(knowledgeBaseId: string, documentId: string): Promise<Document> {
    return this.get<Document>(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/documents/${documentId}`
    );
  }

  async createDocument(
    knowledgeBaseId: string,
    data: {
      name: string;
      source_type: string;
      source_url?: string;
      content_type?: string;
      content?: string;
      metadata?: Record<string, unknown>;
      extraction_config?: Record<string, unknown>;
      expires_at?: string;
    }
  ): Promise<Document> {
    return this.post<Document>(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/documents`,
      data
    );
  }

  async deleteDocument(
    knowledgeBaseId: string,
    documentId: string
  ): Promise<{ success: boolean }> {
    return this.delete(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/documents/${documentId}`
    );
  }

  async processDocument(
    knowledgeBaseId: string,
    documentId: string
  ): Promise<Document> {
    return this.post<Document>(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/documents/${documentId}/process`
    );
  }

  // Embeddings
  async embedChunks(
    knowledgeBaseId: string,
    documentId?: string
  ): Promise<{ embedded_count: number }> {
    return this.post(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/embed`,
      { document_id: documentId },
      { timeout: 60000 }
    );
  }

  // Queries
  async query(
    knowledgeBaseId: string,
    data: {
      query: string;
      strategy?: string;
      top_k?: number;
      threshold?: number;
      filters?: Record<string, unknown>;
      workflow_run_id?: string;
      agent_execution_id?: string;
    }
  ): Promise<QueryResult> {
    return this.post<QueryResult>(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/query`,
      data,
      { timeout: 60000 }
    );
  }

  async getQueryHistory(
    knowledgeBaseId: string,
    filters?: QueryFilters
  ): Promise<{
    queries: RagQuery[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/query_history${queryString}`
    );
  }

  // Data Connectors
  async listConnectors(knowledgeBaseId: string): Promise<{
    connectors: DataConnector[];
  }> {
    return this.get(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/connectors`
    );
  }

  async createConnector(
    knowledgeBaseId: string,
    data: {
      name: string;
      connector_type: string;
      connection_config?: Record<string, unknown>;
      sync_config?: Record<string, unknown>;
      sync_frequency?: string;
    }
  ): Promise<DataConnector> {
    return this.post<DataConnector>(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/connectors`,
      data
    );
  }

  async syncConnector(
    knowledgeBaseId: string,
    connectorId: string
  ): Promise<{ success: boolean; documents_count: number; message: string }> {
    return this.post(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/connectors/${connectorId}/sync`
    );
  }

  // Analytics
  async getAnalytics(
    knowledgeBaseId: string,
    periodDays?: number
  ): Promise<RagAnalytics> {
    const queryString = periodDays ? `?period_days=${periodDays}` : '';
    return this.get<RagAnalytics>(
      `${this.basePath}/knowledge_bases/${knowledgeBaseId}/analytics${queryString}`
    );
  }
}

export const ragApi = new RagApiService();
export default ragApi;
