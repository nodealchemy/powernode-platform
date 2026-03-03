import React, { useRef, useEffect } from 'react';
import { Hash, Radio, Zap, MessageSquare } from 'lucide-react';
import type { TeamChannelSidebarItem } from '@/shared/services/ai/TeamsApiService';

interface ChannelListItemProps {
  channel: TeamChannelSidebarItem;
  isActive: boolean;
  onClick: () => void;
}

const CHANNEL_TYPE_ICONS: Record<string, React.ReactNode> = {
  broadcast: <Radio className="h-3 w-3 text-theme-info" />,
  escalation: <Zap className="h-3 w-3 text-theme-error" />,
};

const CHANNEL_TYPE_COLORS: Record<string, string> = {
  broadcast: 'bg-theme-info/10 text-theme-info',
  direct: 'bg-theme-success/10 text-theme-success',
  topic: 'bg-theme-interactive-primary/10 text-theme-interactive-primary',
  task: 'bg-theme-warning/10 text-theme-warning',
  escalation: 'bg-theme-error/10 text-theme-error',
};

const PLATFORM_LABELS: Record<string, string> = {
  discord: 'DC',
  telegram: 'TG',
  slack: 'SL',
  whatsapp: 'WA',
  mattermost: 'MM',
};

function formatRelativeTime(dateStr: string | null): string {
  if (!dateStr) return '';
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'Now';
  if (diffMins < 60) return `${diffMins}m`;
  if (diffHours < 24) return `${diffHours}h`;
  if (diffDays < 7) return `${diffDays}d`;
  return date.toLocaleDateString();
}

export const ChannelListItem: React.FC<ChannelListItemProps> = ({
  channel,
  isActive,
  onClick,
}) => {
  const itemRef = useRef<HTMLDivElement>(null);
  const typeColor = CHANNEL_TYPE_COLORS[channel.channel_type] || CHANNEL_TYPE_COLORS.topic;

  useEffect(() => {
    if (isActive && itemRef.current) {
      itemRef.current.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }, [isActive]);

  return (
    <div
      ref={itemRef}
      onClick={onClick}
      className={`group flex items-start gap-2 px-3 py-2 cursor-pointer transition-colors ${
        isActive
          ? 'bg-theme-interactive-primary/10 border-l-2 border-theme-interactive-primary'
          : 'hover:bg-theme-surface-hover border-l-2 border-transparent'
      }`}
    >
      <div className="flex-shrink-0 mt-0.5">
        {CHANNEL_TYPE_ICONS[channel.channel_type] || <Hash className="h-3 w-3 text-theme-text-tertiary" />}
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-center justify-between gap-1">
          <div className="flex items-center gap-1 min-w-0">
            <span className="text-sm font-medium text-theme-primary truncate">
              {channel.name}
            </span>
          </div>
          <span className="text-[10px] text-theme-text-tertiary whitespace-nowrap flex-shrink-0">
            {formatRelativeTime(channel.last_activity_at)}
          </span>
        </div>

        <div className="flex items-center gap-1.5 mt-0.5">
          <span className="text-xs text-theme-secondary truncate">
            {channel.team.name}
          </span>

          <span className={`text-[9px] font-semibold uppercase px-1 py-0.5 rounded flex-shrink-0 ${typeColor}`}>
            {channel.channel_type}
          </span>

          {channel.has_active_execution && (
            <span className="h-1.5 w-1.5 rounded-full bg-theme-success animate-pulse flex-shrink-0" title="Active execution" />
          )}
        </div>

        {/* Platform bridge badges + message count */}
        <div className="flex items-center gap-1.5 mt-0.5">
          {channel.linked_platforms.map((platform) => (
            <span
              key={platform}
              className="text-[9px] font-medium px-1 py-0.5 rounded bg-theme-surface-secondary text-theme-text-tertiary"
              title={platform}
            >
              {PLATFORM_LABELS[platform] || platform}
            </span>
          ))}
          {channel.message_count > 0 && (
            <span className="flex items-center gap-0.5 text-[10px] text-theme-text-tertiary ml-auto flex-shrink-0">
              <MessageSquare className="h-2.5 w-2.5" />
              {channel.message_count}
            </span>
          )}
        </div>
      </div>
    </div>
  );
};
