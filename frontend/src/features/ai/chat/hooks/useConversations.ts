import { useState, useEffect, useCallback, useRef } from 'react';
import { conversationsApi } from '@/shared/services/ai';
import { agentsApi } from '@/shared/services/ai';
import type { ConversationBase, ConversationDetail, GlobalConversationFilters } from '@/shared/services/ai/ConversationsApiService';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';

interface UseConversationsOptions {
  pollInterval?: number;
  initialFilters?: GlobalConversationFilters;
}

interface UseConversationsReturn {
  conversations: ConversationBase[];
  activeConversation: ConversationDetail | null;
  loading: boolean;
  loadingConversation: boolean;
  error: string | null;
  filters: GlobalConversationFilters;
  pagination: {
    current_page: number;
    per_page: number;
    total_pages: number;
    total_count: number;
  };
  loadConversations: (filters?: GlobalConversationFilters) => Promise<void>;
  selectConversation: (id: string) => Promise<void>;
  createConversation: (agentId: string, title?: string) => Promise<ConversationBase | null>;
  archiveConversation: (id: string) => Promise<void>;
  deleteConversation: (id: string) => Promise<void>;
  pinConversation: (id: string) => Promise<void>;
  unpinConversation: (id: string) => Promise<void>;
  setFilters: (filters: GlobalConversationFilters) => void;
  clearActiveConversation: () => void;
  bulkAction: (ids: string[], action: string, params?: Record<string, unknown>) => Promise<void>;
  addTag: (id: string, tag: string) => Promise<void>;
  removeTag: (id: string, tag: string) => Promise<void>;
  searchMessages: (query: string) => Promise<ConversationBase[]>;
}

const POLL_INTERVAL_DEFAULT = 30000;

export function useConversations(options: UseConversationsOptions = {}): UseConversationsReturn {
  const { pollInterval = POLL_INTERVAL_DEFAULT, initialFilters } = options;

  const [conversations, setConversations] = useState<ConversationBase[]>([]);
  const [activeConversation, setActiveConversation] = useState<ConversationDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingConversation, setLoadingConversation] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [filters, setFiltersState] = useState<GlobalConversationFilters>(initialFilters || {});
  const [pagination, setPagination] = useState({
    current_page: 1,
    per_page: 25,
    total_pages: 1,
    total_count: 0,
  });

  const { addNotification } = useNotifications();
  const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const mountedRef = useRef(true);

  const loadConversations = useCallback(async (overrideFilters?: GlobalConversationFilters) => {
    try {
      const queryFilters = overrideFilters || filters;
      const response = await conversationsApi.getConversations(queryFilters);

      if (!mountedRef.current) return;

      setConversations(response.items);
      setPagination(response.pagination);
      setError(null);
    } catch (err) {
      if (!mountedRef.current) return;
      const message = err instanceof Error ? err.message : 'Failed to load conversations';
      setError(message);
      logger.error('Failed to load conversations', { error: err });
    } finally {
      if (mountedRef.current) {
        setLoading(false);
      }
    }
  }, [filters]);

  const selectConversation = useCallback(async (id: string) => {
    try {
      setLoadingConversation(true);
      const detail = await conversationsApi.getConversation(id);
      if (!mountedRef.current) return;
      setActiveConversation(detail);
    } catch (err) {
      if (!mountedRef.current) return;
      logger.error('Failed to load conversation', { error: err, conversationId: id });
      addNotification({
        type: 'error',
        title: 'Load Failed',
        message: 'Failed to load conversation details',
      });
    } finally {
      if (mountedRef.current) {
        setLoadingConversation(false);
      }
    }
  }, [addNotification]);

  const createConversation = useCallback(async (agentId: string, title?: string): Promise<ConversationBase | null> => {
    try {
      const result = await agentsApi.createConversation(agentId, {
        title: title || 'New Chat',
      });

      if (!mountedRef.current) return null;

      // Refresh the list
      await loadConversations();

      // Select the new conversation
      if (result?.id) {
        await selectConversation(result.id);
      }

      return result as unknown as ConversationBase;
    } catch (err) {
      if (!mountedRef.current) return null;
      logger.error('Failed to create conversation', { error: err });
      addNotification({
        type: 'error',
        title: 'Create Failed',
        message: 'Failed to create new conversation',
      });
      return null;
    }
  }, [addNotification, loadConversations, selectConversation]);

  const archiveConversation = useCallback(async (id: string) => {
    try {
      await conversationsApi.archiveConversation(id);
      if (!mountedRef.current) return;

      // If archived conversation is active, clear it
      if (activeConversation?.id === id) {
        setActiveConversation(null);
      }

      // Refresh the list
      await loadConversations();

      addNotification({
        type: 'success',
        message: 'Conversation archived',
      });
    } catch (err) {
      if (!mountedRef.current) return;
      logger.error('Failed to archive conversation', { error: err });
      addNotification({
        type: 'error',
        title: 'Archive Failed',
        message: 'Failed to archive conversation',
      });
    }
  }, [activeConversation?.id, addNotification, loadConversations]);

  const deleteConversation = useCallback(async (id: string) => {
    try {
      await conversationsApi.deleteConversation(id);
      if (!mountedRef.current) return;

      // If deleted conversation is active, clear it
      if (activeConversation?.id === id) {
        setActiveConversation(null);
      }

      // Refresh the list
      await loadConversations();

      addNotification({
        type: 'success',
        message: 'Conversation deleted',
      });
    } catch (err) {
      if (!mountedRef.current) return;
      logger.error('Failed to delete conversation', { error: err });
      addNotification({
        type: 'error',
        title: 'Delete Failed',
        message: 'Failed to delete conversation',
      });
    }
  }, [activeConversation?.id, addNotification, loadConversations]);

  const pinConversation = useCallback(async (id: string) => {
    try {
      await conversationsApi.pinConversation(id);
      if (!mountedRef.current) return;

      // Update active conversation if it's the one being pinned
      if (activeConversation?.id === id) {
        setActiveConversation((prev) => prev ? { ...prev, pinned: true, pinned_at: new Date().toISOString() } : null);
      }

      await loadConversations();
    } catch (err) {
      if (!mountedRef.current) return;
      logger.error('Failed to pin conversation', { error: err });
      addNotification({
        type: 'error',
        title: 'Pin Failed',
        message: 'Failed to pin conversation',
      });
    }
  }, [activeConversation?.id, addNotification, loadConversations]);

  const unpinConversation = useCallback(async (id: string) => {
    try {
      await conversationsApi.unpinConversation(id);
      if (!mountedRef.current) return;

      // Update active conversation if it's the one being unpinned
      if (activeConversation?.id === id) {
        setActiveConversation((prev) => prev ? { ...prev, pinned: false, pinned_at: null } : null);
      }

      await loadConversations();
    } catch (err) {
      if (!mountedRef.current) return;
      logger.error('Failed to unpin conversation', { error: err });
      addNotification({
        type: 'error',
        title: 'Unpin Failed',
        message: 'Failed to unpin conversation',
      });
    }
  }, [activeConversation?.id, addNotification, loadConversations]);

  const bulkAction = useCallback(async (ids: string[], action: string, params?: Record<string, unknown>) => {
    try {
      await conversationsApi.bulkAction(ids, action, params);
      if (!mountedRef.current) return;

      // Clear active if it was affected
      if (activeConversation?.id && ids.includes(activeConversation.id)) {
        if (action === 'archive' || action === 'delete') {
          setActiveConversation(null);
        }
      }

      await loadConversations();
      addNotification({
        type: 'success',
        message: `${ids.length} conversation${ids.length > 1 ? 's' : ''} updated`,
      });
    } catch (err) {
      if (!mountedRef.current) return;
      logger.error('Bulk action failed', { error: err, action, count: ids.length });
      addNotification({
        type: 'error',
        title: 'Bulk Action Failed',
        message: 'Failed to perform bulk operation',
      });
    }
  }, [activeConversation?.id, addNotification, loadConversations]);

  const addTag = useCallback(async (id: string, tag: string) => {
    const conv = conversations.find(c => c.id === id);
    const currentTags = conv?.tags || [];
    if (currentTags.includes(tag)) return;

    try {
      await conversationsApi.updateConversation(id, { tags: [...currentTags, tag] });
      if (!mountedRef.current) return;

      // Optimistic update
      setConversations(prev => prev.map(c =>
        c.id === id ? { ...c, tags: [...(c.tags || []), tag] } : c
      ));
      if (activeConversation?.id === id) {
        setActiveConversation(prev => prev ? { ...prev, tags: [...(prev.tags || []), tag] } : null);
      }
    } catch (err) {
      if (!mountedRef.current) return;
      logger.error('Failed to add tag', { error: err, conversationId: id, tag });
      addNotification({ type: 'error', title: 'Tag Failed', message: 'Failed to add tag' });
    }
  }, [conversations, activeConversation?.id, addNotification]);

  const removeTag = useCallback(async (id: string, tag: string) => {
    const conv = conversations.find(c => c.id === id);
    const currentTags = conv?.tags || [];

    try {
      await conversationsApi.updateConversation(id, { tags: currentTags.filter(t => t !== tag) });
      if (!mountedRef.current) return;

      // Optimistic update
      setConversations(prev => prev.map(c =>
        c.id === id ? { ...c, tags: (c.tags || []).filter(t => t !== tag) } : c
      ));
      if (activeConversation?.id === id) {
        setActiveConversation(prev => prev ? { ...prev, tags: (prev.tags || []).filter(t => t !== tag) } : null);
      }
    } catch (err) {
      if (!mountedRef.current) return;
      logger.error('Failed to remove tag', { error: err, conversationId: id, tag });
      addNotification({ type: 'error', title: 'Tag Failed', message: 'Failed to remove tag' });
    }
  }, [conversations, activeConversation?.id, addNotification]);

  const searchMessages = useCallback(async (query: string): Promise<ConversationBase[]> => {
    try {
      const results = await conversationsApi.searchConversations(query);
      return results;
    } catch (err) {
      logger.error('Failed to search messages', { error: err, query });
      addNotification({ type: 'error', title: 'Search Failed', message: 'Failed to search messages' });
      return [];
    }
  }, [addNotification]);

  const setFilters = useCallback((newFilters: GlobalConversationFilters) => {
    setFiltersState(newFilters);
  }, []);

  const clearActiveConversation = useCallback(() => {
    setActiveConversation(null);
  }, []);

  // Initial load
  useEffect(() => {
    loadConversations();
  }, [loadConversations]);

  // Polling
  useEffect(() => {
    if (pollInterval > 0) {
      pollTimerRef.current = setInterval(() => {
        loadConversations();
      }, pollInterval);
    }

    return () => {
      if (pollTimerRef.current) {
        clearInterval(pollTimerRef.current);
      }
    };
  }, [pollInterval, loadConversations]);

  // Cleanup
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  return {
    conversations,
    activeConversation,
    loading,
    loadingConversation,
    error,
    filters,
    pagination,
    loadConversations,
    selectConversation,
    createConversation,
    archiveConversation,
    deleteConversation,
    pinConversation,
    unpinConversation,
    setFilters,
    clearActiveConversation,
    bulkAction,
    addTag,
    removeTag,
    searchMessages,
  };
}
