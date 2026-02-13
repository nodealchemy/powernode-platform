import React, { useState, useCallback } from 'react';
import { ConversationSidebar } from './ConversationSidebar';
import { AgentSelector } from './AgentSelector';
import { useConversations } from '../hooks/useConversations';
import { useChatWindow } from '../context/ChatWindowContext';

type StatusFilter = 'all' | 'active' | 'archived';
type SearchMode = 'title' | 'messages';
type SortOption = 'last_activity' | 'created_at' | 'message_count';

export const ChatWindowSidebar: React.FC = () => {
  const { state, openConversation } = useChatWindow();
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [sortBy, setSortBy] = useState<SortOption>('last_activity');
  const [searchMode, setSearchMode] = useState<SearchMode>('title');
  const [showAgentSelector, setShowAgentSelector] = useState(false);
  const [selectedAgentId, setSelectedAgentId] = useState('');

  const {
    conversations,
    loading,
    archiveConversation,
    deleteConversation,
    pinConversation,
    unpinConversation,
    loadConversations,
    bulkAction,
    addTag,
    removeTag,
    searchMessages,
  } = useConversations({
    initialFilters: statusFilter !== 'all' ? { status: statusFilter } : undefined,
  });

  // Derive active conversation ID from active panel's active tab
  const activePanel = state.panels.find(p => p.id === state.activePanelId);
  const activeTab = activePanel?.activeTabId
    ? state.tabs.find(t => t.id === activePanel.activeTabId)
    : null;
  const activeConversationId = activeTab?.conversationId ?? null;

  const handleSelectConversation = useCallback((id: string) => {
    const conv = conversations.find(c => c.id === id);
    if (conv) {
      const agentId = conv.ai_agent?.id || '';
      const agentName = conv.ai_agent?.name || 'AI Assistant';
      openConversation(agentId, agentName, id);
    }
  }, [conversations, openConversation]);

  const handleNewChat = useCallback(() => {
    setShowAgentSelector(true);
  }, []);

  const handleAgentSelected = useCallback(async () => {
    if (!selectedAgentId) return;
    await openConversation(selectedAgentId, '');
    setShowAgentSelector(false);
    setSelectedAgentId('');
  }, [selectedAgentId, openConversation]);

  const handleSearch = useCallback((query: string) => {
    loadConversations(query ? { search: query } : undefined);
  }, [loadConversations]);

  const handleFilterChange = useCallback((filter: StatusFilter) => {
    setStatusFilter(filter);
    const filters: Record<string, string> = {};
    if (filter !== 'all') filters.status = filter;
    if (sortBy !== 'last_activity') filters.sort_by = sortBy;
    loadConversations(Object.keys(filters).length > 0 ? filters : undefined);
  }, [loadConversations, sortBy]);

  const handleSortChange = useCallback((sort: SortOption) => {
    setSortBy(sort);
    const filters: Record<string, string> = {};
    if (statusFilter !== 'all') filters.status = statusFilter;
    if (sort !== 'last_activity') filters.sort_by = sort;
    loadConversations(Object.keys(filters).length > 0 ? filters : undefined);
  }, [loadConversations, statusFilter]);

  const handleSearchMessages = useCallback(async (query: string) => {
    await searchMessages(query);
  }, [searchMessages]);

  return (
    <div className="relative h-full">
      <ConversationSidebar
        conversations={conversations}
        activeConversationId={activeConversationId}
        loading={loading}
        onSelectConversation={handleSelectConversation}
        onNewChat={handleNewChat}
        onArchive={archiveConversation}
        onDelete={deleteConversation}
        onPin={pinConversation}
        onUnpin={unpinConversation}
        onSearch={handleSearch}
        onFilterChange={handleFilterChange}
        activeFilter={statusFilter}
        onBulkAction={bulkAction}
        onAddTag={addTag}
        onRemoveTag={removeTag}
        onSearchMessages={handleSearchMessages}
        sortBy={sortBy}
        onSortChange={handleSortChange}
        searchMode={searchMode}
        onSearchModeChange={setSearchMode}
      />

      {/* Agent selector modal overlay */}
      {showAgentSelector && (
        <div className="absolute inset-0 z-20 bg-theme-background/90 flex flex-col items-center justify-center p-4">
          <div className="w-full max-w-xs space-y-3">
            <h4 className="text-sm font-semibold text-theme-primary text-center">Select an Agent</h4>
            <AgentSelector
              selectedAgentId={selectedAgentId}
              onSelect={setSelectedAgentId}
            />
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => { setShowAgentSelector(false); setSelectedAgentId(''); }}
                className="flex-1 px-3 py-1.5 text-xs font-medium text-theme-secondary bg-theme-surface border border-theme rounded-md hover:bg-theme-surface-hover transition-colors"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleAgentSelected}
                disabled={!selectedAgentId}
                className="flex-1 px-3 py-1.5 text-xs font-medium text-white bg-theme-interactive-primary rounded-md hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                Start Chat
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
