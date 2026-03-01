import React, { useState, useCallback, useEffect } from 'react';
import { Sparkles, Loader2 } from 'lucide-react';
import { ConversationSidebar } from './ConversationSidebar';
import { AgentSelector } from './AgentSelector';
import { SessionSearch } from './SessionSearch';
import { useConversations } from '../hooks/useConversations';
import { useChatWindow } from '../context/ChatWindowContext';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';
import { teamsApi } from '@/shared/services/ai/TeamsApiService';
import type { TeamChannelSidebarItem } from '@/shared/services/ai/TeamsApiService';

type StatusFilter = 'all' | 'active' | 'archived';
type SearchMode = 'title' | 'messages';
type SortOption = 'last_activity' | 'created_at' | 'message_count';

export const ChatWindowSidebar: React.FC = () => {
  const { state, dispatch, openConversation, openConcierge, openChannel } = useChatWindow();
  const { addNotification } = useNotifications();
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [sortBy, setSortBy] = useState<SortOption>('last_activity');
  const [searchMode, setSearchMode] = useState<SearchMode>('title');
  const [showAgentSelector, setShowAgentSelector] = useState(false);
  const [showWorkspaceCreator, setShowWorkspaceCreator] = useState(false);
  const [selectedAgentId, setSelectedAgentId] = useState('');
  const [conciergeLoading, setConciergeLoading] = useState(false);
  const [channels, setChannels] = useState<TeamChannelSidebarItem[]>([]);

  // Fetch team channels on mount
  useEffect(() => {
    teamsApi.listMyChannels()
      .then(({ channels: chs }) => setChannels(chs))
      .catch((err) => logger.error('Failed to load team channels', err));
  }, []);

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

  // Derive active conversation ID and channel ID from the active tab
  const activeTab = state.activeTabId
    ? state.tabs.find(t => t.id === state.activeTabId)
    : null;
  const activeConversationId = activeTab?.isChannel ? null : (activeTab?.conversationId ?? null);
  const activeChannelId = activeTab?.isChannel ? activeTab.channelId : null;

  const handleSelectChannel = useCallback((channel: TeamChannelSidebarItem) => {
    openChannel(channel.id, channel.name, channel.team.id, channel.team.name);
  }, [openChannel]);

  // Split conversations into workspace vs regular for the sidebar sections
  const workspaceConversations = conversations.filter(c => c.conversation_type === 'team' && c.agent_team?.team_type === 'workspace');
  const regularConversations = conversations.filter(c => !(c.conversation_type === 'team' && c.agent_team?.team_type === 'workspace'));

  const handleSelectConversation = useCallback((id: string) => {
    const conv = conversations.find(c => c.id === id);
    if (conv) {
      const isTeam = conv.conversation_type === 'team';
      const isWorkspace = isTeam && conv.agent_team?.team_type === 'workspace';
      const agentId = conv.ai_agent?.id || '';
      const agentName = isTeam
        ? (conv.agent_team?.name || conv.title || 'Workspace')
        : (conv.ai_agent?.name || 'AI Assistant');
      openConversation(agentId, agentName, id, {
        isWorkspace,
        teamId: isWorkspace && conv.agent_team ? conv.agent_team.id : undefined,
      });
    }
  }, [conversations, openConversation, state.tabs, dispatch]);

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

  const handleCreateWorkspace = useCallback(async (name: string, agentIds: string[]) => {
    try {
      const { workspacesApi } = await import('@/shared/services/ai/WorkspacesApiService');
      const result = await workspacesApi.createWorkspace(name, agentIds);
      const convId = result.workspace.id;
      const primaryAgentId = result.primary_agent?.id || agentIds[0] || '';

      await openConversation(primaryAgentId, name, convId, {
        isWorkspace: true,
        teamId: result.team.id,
      });

      setShowWorkspaceCreator(false);
      loadConversations();
      addNotification({ type: 'success', title: 'Workspace created', message: `"${name}" is ready` });
    } catch (err) {
      logger.error('Failed to create workspace', err);
      addNotification({ type: 'error', title: 'Failed to create workspace', message: 'Please try again' });
    }
  }, [openConversation, loadConversations, addNotification]);

  return (
    <div className="relative h-full">
      <ConversationSidebar
        conversations={regularConversations}
        workspaceConversations={workspaceConversations}
        activeConversationId={activeConversationId}
        loading={loading}
        onSelectConversation={handleSelectConversation}
        onNewChat={handleNewChat}
        onNewWorkspace={() => setShowWorkspaceCreator(true)}
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
        channels={channels}
        activeChannelId={activeChannelId}
        onSelectChannel={handleSelectChannel}
      />

      {/* Agent selector modal overlay */}
      {showAgentSelector && (
        <div className="absolute inset-0 z-20 bg-theme-background flex flex-col items-center justify-start p-4 pt-4 overflow-y-auto">
          <div className="w-full max-w-xs space-y-3">
            <h4 className="text-sm font-semibold text-theme-primary text-center">New Conversation</h4>
            <button
              type="button"
              onClick={async () => {
                setConciergeLoading(true);
                try {
                  await openConcierge();
                  setShowAgentSelector(false);
                } finally {
                  setConciergeLoading(false);
                }
              }}
              disabled={conciergeLoading}
              className="w-full px-3 py-2.5 text-sm font-medium text-white bg-theme-interactive-primary rounded-md hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex items-center justify-center gap-2"
            >
              {conciergeLoading ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Sparkles className="h-4 w-4" />
              )}
              Chat with Concierge
            </button>
            <div className="flex items-center gap-3">
              <div className="flex-1 h-px bg-theme-border" />
              <span className="text-[10px] text-theme-text-tertiary">or choose an agent</span>
              <div className="flex-1 h-px bg-theme-border" />
            </div>
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

      {/* Workspace creator modal overlay */}
      {showWorkspaceCreator && (
        <div className="absolute inset-0 z-20">
          <SessionSearch
            onCreateWorkspace={handleCreateWorkspace}
            onClose={() => setShowWorkspaceCreator(false)}
          />
        </div>
      )}
    </div>
  );
};
