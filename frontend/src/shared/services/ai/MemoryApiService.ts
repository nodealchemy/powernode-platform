import { BaseApiService, PaginatedResponse } from '@/shared/services/ai/BaseApiService';
import type {
  MemoryEntry,
  MemoryFilters,
  CreateMemoryRequest,
  UpdateMemoryRequest,
  MemorySearchRequest,
  MemorySearchResponse,
  ContextInjectionRequest,
  ContextInjectionResponse,
  MemoryStatsResponse,
} from '@/shared/services/ai/types/memory-types';

/**
 * MemoryApiService - Agent Memory API Client
 *
 * Provides access to the persistent memory system for AI agents.
 * Supports factual, experiential, and working memory types.
 *
 * Endpoint structure:
 * - GET    /api/v1/ai/agents/:agent_id/memory
 * - POST   /api/v1/ai/agents/:agent_id/memory
 * - GET    /api/v1/ai/agents/:agent_id/memory/stats
 * - POST   /api/v1/ai/agents/:agent_id/memory/search
 * - POST   /api/v1/ai/agents/:agent_id/memory/clear
 * - POST   /api/v1/ai/agents/:agent_id/memory/sync
 * - POST   /api/v1/ai/agents/:agent_id/memory/inject
 * - GET    /api/v1/ai/agents/:agent_id/memory/:key
 * - PATCH  /api/v1/ai/agents/:agent_id/memory/:key
 * - DELETE /api/v1/ai/agents/:agent_id/memory/:key
 */

class MemoryApiService extends BaseApiService {
  private buildMemoryPath(agentId: string, suffix?: string): string {
    let path = `${this.baseNamespace}/agents/${agentId}/memory`;
    if (suffix) {
      path += `/${suffix}`;
    }
    return path;
  }

  // ===================================================================
  // Memory CRUD Operations
  // ===================================================================

  /**
   * Get list of memories for an agent
   * GET /api/v1/ai/agents/:agent_id/memory
   */
  async getMemories(agentId: string, filters?: MemoryFilters): Promise<PaginatedResponse<MemoryEntry>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<MemoryEntry>>(this.buildMemoryPath(agentId) + queryString);
  }

  /**
   * Get single memory by key
   * GET /api/v1/ai/agents/:agent_id/memory/:key
   */
  async getMemory(agentId: string, key: string): Promise<{ memory: MemoryEntry }> {
    return this.get<{ memory: MemoryEntry }>(this.buildMemoryPath(agentId, key));
  }

  /**
   * Create new memory entry
   * POST /api/v1/ai/agents/:agent_id/memory
   */
  async createMemory(agentId: string, data: CreateMemoryRequest): Promise<{ memory: MemoryEntry }> {
    return this.post<{ memory: MemoryEntry }>(this.buildMemoryPath(agentId), data);
  }

  /**
   * Update existing memory
   * PATCH /api/v1/ai/agents/:agent_id/memory/:key
   */
  async updateMemory(agentId: string, key: string, data: UpdateMemoryRequest): Promise<{ memory: MemoryEntry }> {
    return this.patch<{ memory: MemoryEntry }>(this.buildMemoryPath(agentId, key), data);
  }

  /**
   * Delete memory
   * DELETE /api/v1/ai/agents/:agent_id/memory/:key
   */
  async deleteMemory(agentId: string, key: string): Promise<{ message: string }> {
    return this.delete<{ message: string }>(this.buildMemoryPath(agentId, key));
  }

  // ===================================================================
  // Memory Operations
  // ===================================================================

  /**
   * Get memory statistics for an agent
   * GET /api/v1/ai/agents/:agent_id/memory/stats
   */
  async getStats(agentId: string): Promise<MemoryStatsResponse> {
    return this.get<MemoryStatsResponse>(this.buildMemoryPath(agentId, 'stats'));
  }

  /**
   * Search memories semantically
   * POST /api/v1/ai/agents/:agent_id/memory/search
   */
  async searchMemories(agentId: string, request: MemorySearchRequest): Promise<MemorySearchResponse> {
    return this.post<MemorySearchResponse>(this.buildMemoryPath(agentId, 'search'), request);
  }

  /**
   * Clear all memories for an agent
   * POST /api/v1/ai/agents/:agent_id/memory/clear
   */
  async clearMemories(agentId: string, memoryType?: string): Promise<{ message: string; deleted_count: number }> {
    return this.post<{ message: string; deleted_count: number }>(
      this.buildMemoryPath(agentId, 'clear'),
      { memory_type: memoryType }
    );
  }

  /**
   * Sync memories to persistent storage
   * POST /api/v1/ai/agents/:agent_id/memory/sync
   */
  async syncMemories(agentId: string): Promise<{ message: string }> {
    return this.post<{ message: string }>(this.buildMemoryPath(agentId, 'sync'));
  }

  /**
   * Get context injection for a task
   * POST /api/v1/ai/agents/:agent_id/memory/inject
   */
  async getContextInjection(agentId: string, request: ContextInjectionRequest): Promise<ContextInjectionResponse> {
    return this.post<ContextInjectionResponse>(this.buildMemoryPath(agentId, 'inject'), request);
  }

  // ===================================================================
  // Convenience Methods
  // ===================================================================

  /**
   * Store a factual memory
   */
  async storeFact(agentId: string, key: string, value: unknown, metadata?: Record<string, unknown>): Promise<{ memory: MemoryEntry }> {
    return this.createMemory(agentId, {
      entry_key: key,
      memory_type: 'factual',
      entry_type: 'fact',
      content: typeof value === 'string' ? { text: value, value } : value as Record<string, unknown>,
      metadata,
    });
  }

  /**
   * Store an experiential memory
   */
  async storeExperience(
    agentId: string,
    content: string | Record<string, unknown>,
    options?: {
      tags?: string[];
      outcomeSuccess?: boolean;
      taskContext?: Record<string, unknown>;
      importance?: number;
    }
  ): Promise<{ memory: MemoryEntry }> {
    return this.createMemory(agentId, {
      memory_type: 'experiential',
      entry_type: 'memory',
      content: typeof content === 'string' ? { text: content } : content,
      tags: options?.tags,
      outcome_success: options?.outcomeSuccess,
      task_context: options?.taskContext,
      importance: options?.importance,
    });
  }

  /**
   * Get factual memories
   */
  async getFactualMemories(agentId: string, limit?: number): Promise<PaginatedResponse<MemoryEntry>> {
    return this.getMemories(agentId, { memory_type: 'factual', limit });
  }

  /**
   * Get experiential memories
   */
  async getExperientialMemories(agentId: string, limit?: number): Promise<PaginatedResponse<MemoryEntry>> {
    return this.getMemories(agentId, { memory_type: 'experiential', limit });
  }

  /**
   * Get successful outcomes
   */
  async getSuccessfulOutcomes(agentId: string, limit?: number): Promise<PaginatedResponse<MemoryEntry>> {
    return this.getMemories(agentId, { memory_type: 'experiential', outcome_success: true, limit });
  }

  /**
   * Get failed outcomes
   */
  async getFailedOutcomes(agentId: string, limit?: number): Promise<PaginatedResponse<MemoryEntry>> {
    return this.getMemories(agentId, { memory_type: 'experiential', outcome_success: false, limit });
  }

  /**
   * Search for similar experiences
   */
  async findSimilarExperiences(agentId: string, query: string, limit?: number): Promise<MemorySearchResponse> {
    return this.searchMemories(agentId, {
      query,
      memory_type: 'experiential',
      limit: limit || 10,
    });
  }

  // ===================================================================
  // Memory Pool Operations
  // ===================================================================

  /**
   * Get all memory pools
   * GET /api/v1/ai/memory_pools
   */
  async getMemoryPools(): Promise<PaginatedResponse<Record<string, unknown>>> {
    return this.get<PaginatedResponse<Record<string, unknown>>>(`${this.baseNamespace}/memory_pools`);
  }

  /**
   * Create a memory pool
   * POST /api/v1/ai/memory_pools
   */
  async createMemoryPool(params: Record<string, unknown>): Promise<Record<string, unknown>> {
    return this.post<Record<string, unknown>>(`${this.baseNamespace}/memory_pools`, params);
  }

  /**
   * Update a memory pool
   * PATCH /api/v1/ai/memory_pools/:poolId
   */
  async updateMemoryPool(poolId: string, params: Record<string, unknown>): Promise<Record<string, unknown>> {
    return this.patch<Record<string, unknown>>(`${this.baseNamespace}/memory_pools/${poolId}`, params);
  }

  /**
   * Delete a memory pool
   * DELETE /api/v1/ai/memory_pools/:poolId
   */
  async deleteMemoryPool(poolId: string): Promise<{ message: string }> {
    return this.delete<{ message: string }>(`${this.baseNamespace}/memory_pools/${poolId}`);
  }

  /**
   * Read data from a pool by key
   * GET /api/v1/ai/memory_pools/:poolId/data/:key
   */
  async readPoolData(poolId: string, key: string): Promise<Record<string, unknown>> {
    return this.get<Record<string, unknown>>(`${this.baseNamespace}/memory_pools/${poolId}/data/${key}`);
  }

  /**
   * Write data to a pool
   * POST /api/v1/ai/memory_pools/:poolId/data
   */
  async writePoolData(poolId: string, data: Record<string, unknown>): Promise<Record<string, unknown>> {
    return this.post<Record<string, unknown>>(`${this.baseNamespace}/memory_pools/${poolId}/data`, data);
  }

  /**
   * Query a pool
   * POST /api/v1/ai/memory_pools/:poolId/query
   */
  async queryPool(poolId: string, query: Record<string, unknown>): Promise<Record<string, unknown>> {
    return this.post<Record<string, unknown>>(`${this.baseNamespace}/memory_pools/${poolId}/query`, query);
  }
}

// Export singleton instance
export const memoryApiService = new MemoryApiService();
export default memoryApiService;
