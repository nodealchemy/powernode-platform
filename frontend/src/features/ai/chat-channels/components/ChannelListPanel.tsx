import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { Search, MessageSquare, RefreshCw } from 'lucide-react';
import { ResizableListPanel } from '@/shared/components/layout/ResizableListPanel';
import { Loading } from '@/shared/components/ui/Loading';
import { Badge } from '@/shared/components/ui/Badge';
import { chatChannelsApi } from '@/shared/services/ai';
import { cn } from '@/shared/utils/cn';
import type { ChatChannelSummary, ChannelFilters, ChannelStatus } from '@/shared/services/ai';

interface ChannelListPanelProps {
  selectedChannelId: string | null;
  onSelectChannel: (channel: ChatChannelSummary) => void;
  refreshKey?: number;
}

const statusConfig: Record<ChannelStatus, { variant: 'success' | 'danger' | 'warning' | 'outline'; label: string; dot: string }> = {
  active: { variant: 'success', label: 'Connected', dot: 'bg-theme-success' },
  inactive: { variant: 'outline', label: 'Inactive', dot: 'bg-theme-muted' },
  error: { variant: 'danger', label: 'Error', dot: 'bg-theme-danger' },
  disconnected: { variant: 'warning', label: 'Disconnected', dot: 'bg-theme-warning' },
};

type TabFilter = 'all' | ChannelStatus;

const filterTabs: { key: TabFilter; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'active', label: 'Connected' },
  { key: 'inactive', label: 'Inactive' },
  { key: 'disconnected', label: 'Disconnected' },
  { key: 'error', label: 'Error' },
];

function formatTime(timestamp?: string): string {
  if (!timestamp) return 'Never';
  const date = new Date(timestamp);
  const now = new Date();
  const diff = now.getTime() - date.getTime();
  if (diff < 60000) return 'Just now';
  if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
  return date.toLocaleDateString();
}

export const ChannelListPanel: React.FC<ChannelListPanelProps> = ({
  selectedChannelId,
  onSelectChannel,
  refreshKey,
}) => {
  const [channels, setChannels] = useState<ChatChannelSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<TabFilter>('all');
  const [searchQuery, setSearchQuery] = useState('');

  const loadChannels = useCallback(async () => {
    try {
      setLoading(true);
      const filters: ChannelFilters = { per_page: 50 };
      if (activeTab !== 'all') filters.status = activeTab;
      const response = await chatChannelsApi.getChannels(filters);
      setChannels(response.items || []);
    } catch {
      setChannels([]);
    } finally {
      setLoading(false);
    }
  }, [activeTab]);

  useEffect(() => {
    loadChannels();
  }, [loadChannels, refreshKey]);

  const filteredChannels = useMemo(() => {
    if (!searchQuery) return channels;
    const q = searchQuery.toLowerCase();
    return channels.filter(
      (ch) =>
        ch.name.toLowerCase().includes(q) ||
        ch.platform.toLowerCase().includes(q)
    );
  }, [channels, searchQuery]);

  const stats = useMemo(() => {
    const active = channels.filter((c) => c.status === 'active').length;
    return { total: channels.length, active };
  }, [channels]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (filteredChannels.length === 0) return;
      const currentIndex = filteredChannels.findIndex((c) => c.id === selectedChannelId);

      if (e.key === 'ArrowDown') {
        e.preventDefault();
        const next = currentIndex < filteredChannels.length - 1 ? currentIndex + 1 : 0;
        onSelectChannel(filteredChannels[next]);
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        const prev = currentIndex > 0 ? currentIndex - 1 : filteredChannels.length - 1;
        onSelectChannel(filteredChannels[prev]);
      }
    },
    [filteredChannels, selectedChannelId, onSelectChannel]
  );

  const tabPills = (
    <div className="flex flex-wrap gap-1 px-3 py-2 border-b border-theme">
      {filterTabs.map((tab) => (
        <button
          key={tab.key}
          onClick={() => setActiveTab(tab.key)}
          className={cn(
            'px-2 py-0.5 text-xs rounded-full transition-colors',
            activeTab === tab.key
              ? 'bg-theme-interactive-primary text-white'
              : 'text-theme-secondary hover:bg-theme-surface-hover'
          )}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );

  const search = (
    <div className="px-3 py-2 border-b border-theme">
      <div className="relative">
        <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-theme-muted" />
        <input
          type="text"
          placeholder="Search channels..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="w-full pl-7 pr-2 py-1.5 text-xs bg-theme-surface-dark border border-theme rounded text-theme-primary placeholder:text-theme-muted focus:outline-none focus:border-theme-interactive-primary"
        />
      </div>
    </div>
  );

  const footer = (
    <div className="px-3 py-2 border-t border-theme text-xs text-theme-muted flex items-center gap-3">
      <span>{stats.total} channels</span>
      <span>{stats.active} connected</span>
    </div>
  );

  const collapsedContent = (
    <>
      {filteredChannels.slice(0, 10).map((ch) => {
        const cfg = statusConfig[ch.status] || statusConfig.inactive;
        return (
          <button
            key={ch.id}
            onClick={() => onSelectChannel(ch)}
            className={cn(
              'w-8 h-8 rounded flex items-center justify-center transition-colors',
              ch.id === selectedChannelId
                ? 'bg-theme-interactive-primary/20'
                : 'hover:bg-theme-surface-hover'
            )}
            title={`${ch.name} - ${cfg.label}`}
          >
            <div className={cn('w-2.5 h-2.5 rounded-full', cfg.dot)} />
          </button>
        );
      })}
    </>
  );

  return (
    <ResizableListPanel
      storageKeyPrefix="ai-chat-channels"
      title="Chat Channels"
      headerAction={
        <button
          onClick={loadChannels}
          className="p-1 rounded text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors"
          title="Refresh channels"
        >
          <RefreshCw className={cn('h-4 w-4', loading && 'animate-spin')} />
        </button>
      }
      tabPills={tabPills}
      search={search}
      footer={footer}
      collapsedContent={collapsedContent}
      onKeyDown={handleKeyDown}
    >
      {loading ? (
        <div className="flex items-center justify-center py-8">
          <Loading size="sm" message="Loading..." />
        </div>
      ) : filteredChannels.length === 0 ? (
        <div className="px-3 py-8 text-center">
          <MessageSquare size={24} className="mx-auto text-theme-secondary mb-2" />
          <p className="text-xs text-theme-secondary">
            {searchQuery ? 'No channels match your search' : 'No channels configured'}
          </p>
        </div>
      ) : (
        <div className="py-1">
          {filteredChannels.map((channel) => {
            const cfg = statusConfig[channel.status] || statusConfig.inactive;
            return (
              <button
                key={channel.id}
                onClick={() => onSelectChannel(channel)}
                className={cn(
                  'w-full text-left px-3 py-2.5 border-b border-theme/50 transition-colors border-l-2',
                  channel.id === selectedChannelId
                    ? 'bg-theme-interactive-primary/10 border-l-theme-interactive-primary'
                    : 'hover:bg-theme-surface-hover border-l-transparent'
                )}
              >
                <div className="flex items-center justify-between mb-1">
                  <span className="text-sm font-medium text-theme-primary truncate">
                    {channel.name}
                  </span>
                  <Badge variant={cfg.variant} size="xs">{cfg.label}</Badge>
                </div>
                <div className="flex items-center gap-2 text-[11px] text-theme-secondary">
                  <span className="capitalize">{channel.platform}</span>
                  <span className="flex items-center gap-1">
                    <MessageSquare className="w-3 h-3" />
                    {channel.total_sessions}
                  </span>
                  <span>{formatTime(channel.last_message_at)}</span>
                </div>
              </button>
            );
          })}
        </div>
      )}
    </ResizableListPanel>
  );
};

export default ChannelListPanel;
