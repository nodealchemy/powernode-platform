import React, { useState, useEffect, useCallback } from 'react';
import {
  Plus,
  Search,
  RefreshCw,
  MessageSquare,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { chatChannelsApi } from '@/shared/services/ai';
import { ChannelCard } from './ChannelCard';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { cn } from '@/shared/utils/cn';
import type { ChatChannelSummary, ChatPlatform, ChannelFilters } from '@/shared/services/ai';

interface ChannelListProps {
  onSelectChannel?: (channel: ChatChannelSummary) => void;
  onCreateChannel?: () => void;
  onSettingsChannel?: (channel: ChatChannelSummary) => void;
  className?: string;
}

const platformOptions = [
  { value: '', label: 'All Platforms' },
  { value: 'telegram', label: 'Telegram' },
  { value: 'discord', label: 'Discord' },
  { value: 'slack', label: 'Slack' },
  { value: 'whatsapp', label: 'WhatsApp' },
  { value: 'mattermost', label: 'Mattermost' },
];

const statusOptions = [
  { value: '', label: 'All Status' },
  { value: 'active', label: 'Connected' },
  { value: 'inactive', label: 'Inactive' },
  { value: 'disconnected', label: 'Disconnected' },
  { value: 'error', label: 'Error' },
];

export const ChannelList: React.FC<ChannelListProps> = ({
  onSelectChannel,
  onCreateChannel,
  onSettingsChannel,
  className,
}) => {
  const [channels, setChannels] = useState<ChatChannelSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [platformFilter, setPlatformFilter] = useState<string>('');
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [searchQuery, setSearchQuery] = useState('');
  const [totalCount, setTotalCount] = useState(0);

  const loadChannels = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const filters: ChannelFilters = { per_page: 50 };
      if (platformFilter) filters.platform = platformFilter as ChatPlatform;
      if (statusFilter) filters.status = statusFilter as ChannelFilters['status'];

      const response = await chatChannelsApi.getChannels(filters);
      setChannels(response.items || []);
      setTotalCount(response.pagination?.total_count || 0);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load channels');
    } finally {
      setLoading(false);
    }
  }, [platformFilter, statusFilter]);

  useEffect(() => {
    loadChannels();
  }, [loadChannels]);

  const handleConnect = async (channel: ChatChannelSummary) => {
    try {
      await chatChannelsApi.connectChannel(channel.id);
      loadChannels();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to connect channel');
    }
  };

  const handleDisconnect = async (channel: ChatChannelSummary) => {
    try {
      await chatChannelsApi.disconnectChannel(channel.id);
      loadChannels();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to disconnect channel');
    }
  };

  // Filter channels by search query locally
  const filteredChannels = searchQuery
    ? channels.filter(
        (channel) =>
          channel.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
          channel.platform.toLowerCase().includes(searchQuery.toLowerCase())
      )
    : channels;

  if (loading && channels.length === 0) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loading size="lg" />
      </div>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-theme-text-primary">Chat Channels</h2>
          <p className="text-sm text-theme-text-secondary">
            {totalCount} channel{totalCount !== 1 ? 's' : ''} connected
          </p>
        </div>
        <Button variant="primary" onClick={onCreateChannel}>
          <Plus className="w-4 h-4 mr-2" />
          Add Channel
        </Button>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-4">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-text-secondary" />
          <Input
            placeholder="Search channels..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-10"
          />
        </div>
        <Select
          value={platformFilter}
          onChange={(value) => setPlatformFilter(value)}
          className="w-40"
        >
          {platformOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
        <Select
          value={statusFilter}
          onChange={(value) => setStatusFilter(value)}
          className="w-40"
        >
          {statusOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
        <Button variant="ghost" onClick={loadChannels} disabled={loading}>
          <RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} />
        </Button>
      </div>

      {/* Error */}
      {error && <ErrorAlert message={error} />}

      {/* Channel Grid */}
      {filteredChannels.length === 0 ? (
        <EmptyState
          icon={MessageSquare}
          title="No channels found"
          description={
            searchQuery || platformFilter || statusFilter
              ? 'Try adjusting your filters'
              : 'Connect your first chat platform to get started'
          }
          action={
            !searchQuery && !platformFilter && !statusFilter ? (
              <Button variant="primary" onClick={onCreateChannel}>
                <Plus className="w-4 h-4 mr-2" />
                Add Channel
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredChannels.map((channel) => (
            <ChannelCard
              key={channel.id}
              channel={channel}
              onSelect={onSelectChannel}
              onConnect={handleConnect}
              onDisconnect={handleDisconnect}
              onSettings={onSettingsChannel}
            />
          ))}
        </div>
      )}
    </div>
  );
};

export default ChannelList;
