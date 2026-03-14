import { api } from '@/shared/services/api';
import type {
  ContextsResponse,
  ContextResponse,
  EntriesResponse,
  EntryResponse,
  SearchResponse,
  AgentMemoryResponse,
  ContextStatsResponse,
  ExportResponse,
  ImportResponse,
  ContextFormData,
  EntryFormData,
  ContextFilters,
  EntryFilters,
  SearchParams,
  ContextType,
  ContextScope,
  EntryType,
} from '../types';

const handleApiError = (error: unknown, defaultMessage: string): string => {
  if (error && typeof error === 'object' && 'response' in error) {
    return (error as { response?: { data?: { error?: string } } }).response?.data?.error || defaultMessage;
  }
  return defaultMessage;
};

export const contextApi = {
  // ==================== Contexts ====================

  async getContexts(
    page = 1,
    perPage = 20,
    filters?: ContextFilters
  ): Promise<ContextsResponse> {
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        per_page: perPage.toString(),
      });

      if (filters?.context_type) params.append('context_type', filters.context_type);
      if (filters?.scope) params.append('scope', filters.scope);
      if (filters?.ai_agent_id) params.append('ai_agent_id', filters.ai_agent_id);
      if (filters?.is_archived !== undefined) params.append('is_archived', String(filters.is_archived));

      const response = await api.get(`/ai/contexts?${params}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch contexts'),
      };
    }
  },

  async getContext(id: string): Promise<ContextResponse> {
    try {
      const response = await api.get(`/ai/contexts/${id}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch context'),
      };
    }
  },

  async createContext(data: ContextFormData): Promise<ContextResponse> {
    try {
      const response = await api.post('/ai/contexts', { context: data });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to create context'),
      };
    }
  },

  async updateContext(id: string, data: Partial<ContextFormData>): Promise<ContextResponse> {
    try {
      const response = await api.patch(`/ai/contexts/${id}`, { context: data });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to update context'),
      };
    }
  },

  async deleteContext(id: string): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.delete(`/ai/contexts/${id}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to delete context'),
      };
    }
  },

  async archiveContext(id: string): Promise<ContextResponse> {
    try {
      const response = await api.post(`/ai/contexts/${id}/archive`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to archive context'),
      };
    }
  },

  async restoreContext(id: string): Promise<ContextResponse> {
    try {
      const response = await api.post(`/ai/contexts/${id}/restore`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to restore context'),
      };
    }
  },

  async cloneContext(id: string, name: string): Promise<ContextResponse> {
    try {
      const response = await api.post(`/ai/contexts/${id}/clone`, { name });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to clone context'),
      };
    }
  },

  async getContextStats(id: string): Promise<ContextStatsResponse> {
    try {
      const response = await api.get(`/ai/contexts/${id}/stats`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch context stats'),
      };
    }
  },

  // ==================== Entries ====================

  async getEntries(
    contextId: string,
    page = 1,
    perPage = 20,
    filters?: EntryFilters
  ): Promise<EntriesResponse> {
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        per_page: perPage.toString(),
      });

      if (filters?.entry_type) params.append('entry_type', filters.entry_type);
      if (filters?.min_importance) params.append('min_importance', filters.min_importance.toString());
      if (filters?.tags?.length) params.append('tags', filters.tags.join(','));
      if (filters?.has_embedding !== undefined) params.append('has_embedding', String(filters.has_embedding));
      if (filters?.q) params.append('q', filters.q);

      const response = await api.get(`/ai/contexts/${contextId}/entries?${params}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch entries'),
      };
    }
  },

  async getEntry(contextId: string, entryId: string): Promise<EntryResponse> {
    try {
      const response = await api.get(`/ai/contexts/${contextId}/entries/${entryId}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch entry'),
      };
    }
  },

  async createEntry(contextId: string, data: EntryFormData): Promise<EntryResponse> {
    try {
      const response = await api.post(`/ai/contexts/${contextId}/entries`, { entry: data });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to create entry'),
      };
    }
  },

  async updateEntry(
    contextId: string,
    entryId: string,
    data: Partial<EntryFormData>
  ): Promise<EntryResponse> {
    try {
      const response = await api.patch(`/ai/contexts/${contextId}/entries/${entryId}`, {
        entry: data,
      });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to update entry'),
      };
    }
  },

  async deleteEntry(
    contextId: string,
    entryId: string
  ): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.delete(`/ai/contexts/${contextId}/entries/${entryId}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to delete entry'),
      };
    }
  },

  async bulkDeleteEntries(
    contextId: string,
    entryIds: string[]
  ): Promise<{ success: boolean; deleted?: number; error?: string }> {
    try {
      const response = await api.post(`/ai/contexts/${contextId}/entries/bulk_delete`, {
        entry_ids: entryIds,
      });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to delete entries'),
      };
    }
  },

  // ==================== Search ====================

  async search(params: SearchParams): Promise<SearchResponse> {
    try {
      const response = await api.post('/ai/contexts/search', params);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to search'),
      };
    }
  },

  async searchInContext(contextId: string, params: SearchParams): Promise<SearchResponse> {
    try {
      const response = await api.post(`/ai/contexts/${contextId}/search`, params);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to search context'),
      };
    }
  },

  // ==================== Agent Memory ====================

  async getAgentMemory(
    agentId: string,
    page = 1,
    perPage = 20,
    filters?: EntryFilters
  ): Promise<AgentMemoryResponse> {
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        per_page: perPage.toString(),
      });

      if (filters?.entry_type) params.append('entry_type', filters.entry_type);
      if (filters?.min_importance) params.append('min_importance', filters.min_importance.toString());
      if (filters?.tags?.length) params.append('tags', filters.tags.join(','));

      const response = await api.get(`/ai/agents/${agentId}/memory?${params}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch agent memory'),
      };
    }
  },

  async addAgentMemory(agentId: string, data: EntryFormData): Promise<EntryResponse> {
    try {
      const response = await api.post(`/ai/agents/${agentId}/memory`, { entry: data });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to add memory'),
      };
    }
  },

  async clearAgentMemory(
    agentId: string,
    entryTypes?: EntryType[]
  ): Promise<{ success: boolean; cleared?: number; error?: string }> {
    try {
      const response = await api.post(`/ai/agents/${agentId}/memory/clear`, {
        entry_types: entryTypes,
      });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to clear memory'),
      };
    }
  },

  // ==================== Import/Export ====================

  async exportContext(
    contextId: string,
    format: 'json' | 'csv' = 'json'
  ): Promise<ExportResponse> {
    try {
      const response = await api.post(`/ai/contexts/${contextId}/export`, { format });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to export context'),
      };
    }
  },

  async importToContext(contextId: string, file: File): Promise<ImportResponse> {
    try {
      const formData = new FormData();
      formData.append('file', file);

      const response = await api.post(`/ai/contexts/${contextId}/import`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to import to context'),
      };
    }
  },

  // ==================== Helpers ====================

  getContextTypeLabel(type: ContextType): string {
    switch (type) {
      case 'agent_memory':
        return 'Agent Memory';
      case 'knowledge_base':
        return 'Knowledge Base';
      case 'shared_context':
        return 'Shared Context';
      default:
        return type;
    }
  },

  getContextTypeIcon(type: ContextType): string {
    switch (type) {
      case 'agent_memory':
        return '🧠';
      case 'knowledge_base':
        return '📚';
      case 'shared_context':
        return '🔗';
      default:
        return '📦';
    }
  },

  getScopeLabel(scope: ContextScope): string {
    switch (scope) {
      case 'account':
        return 'Account';
      case 'agent':
        return 'Agent';
      case 'team':
        return 'Team';
      case 'workflow':
        return 'Workflow';
      default:
        return scope;
    }
  },

  getEntryTypeLabel(type: EntryType): string {
    switch (type) {
      case 'fact':
        return 'Fact';
      case 'preference':
        return 'Preference';
      case 'interaction':
        return 'Interaction';
      case 'knowledge':
        return 'Knowledge';
      case 'skill':
        return 'Skill';
      case 'relationship':
        return 'Relationship';
      case 'goal':
        return 'Goal';
      case 'constraint':
        return 'Constraint';
      default:
        return type;
    }
  },

  getEntryTypeColor(type: EntryType): string {
    switch (type) {
      case 'fact':
        return 'bg-theme-blue text-theme-blue';
      case 'preference':
        return 'bg-theme-amber text-theme-amber';
      case 'interaction':
        return 'bg-theme-violet text-theme-violet';
      case 'knowledge':
        return 'bg-theme-emerald text-theme-emerald';
      case 'skill':
        return 'bg-theme-cyan text-theme-cyan';
      case 'relationship':
        return 'bg-theme-pink text-theme-pink';
      case 'goal':
        return 'bg-theme-rose text-theme-rose';
      case 'constraint':
        return 'bg-theme-orange text-theme-orange';
      default:
        return 'bg-theme-surface text-theme-secondary';
    }
  },

  formatBytes(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
  },

  formatImportanceScore(score: number): string {
    if (score >= 0.8) return 'High';
    if (score >= 0.5) return 'Medium';
    if (score >= 0.2) return 'Low';
    return 'Minimal';
  },

  getImportanceColor(score: number): string {
    if (score >= 0.8) return 'text-theme-error';
    if (score >= 0.5) return 'text-theme-warning';
    if (score >= 0.2) return 'text-theme-info';
    return 'text-theme-tertiary';
  },
};
