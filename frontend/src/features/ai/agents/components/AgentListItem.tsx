import React from 'react';
import { MoreHorizontal, Copy, Pause, Play, Archive } from 'lucide-react';
import { DropdownMenu } from '@/shared/components/ui/DropdownMenu';
import type { AiAgent } from '@/shared/types/ai';

type AgentStatus = AiAgent['status'];

const STATUS_STYLES: Record<AgentStatus, { dot: string; pulse?: boolean }> = {
  active: { dot: 'bg-theme-success' },
  inactive: { dot: 'bg-theme-secondary' },
  error: { dot: 'bg-theme-error', pulse: true },
};

function timeAgo(dateStr: string | undefined): string {
  if (!dateStr) return '';
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

interface AgentListItemProps {
  agent: AiAgent;
  isSelected: boolean;
  onClick: () => void;
  onClone?: (agent: AiAgent) => void;
  onToggleStatus?: (agent: AiAgent) => void;
  onArchive?: (agent: AiAgent) => void;
  canManage?: boolean;
}

export const AgentListItem: React.FC<AgentListItemProps> = ({
  agent,
  isSelected,
  onClick,
  onClone,
  onToggleStatus,
  onArchive,
  canManage,
}) => {
  const statusStyle = STATUS_STYLES[agent.status] || STATUS_STYLES.inactive;
  const executions = agent.execution_stats?.total_executions || 0;

  const menuItems = [
    { icon: Copy, label: 'Clone', onClick: () => onClone?.(agent) },
    {
      icon: agent.status === 'active' ? Pause : Play,
      label: agent.status === 'active' ? 'Pause' : 'Resume',
      onClick: () => onToggleStatus?.(agent),
    },
    { icon: Archive, label: 'Archive', onClick: () => onArchive?.(agent) },
  ];

  return (
    <div className="relative group">
      <button
        onClick={onClick}
        data-list-item
        className={`w-full text-left px-3 py-2.5 border-l-2 transition-colors hover:bg-theme-surface-hover ${
          isSelected
            ? 'border-l-theme-accent bg-theme-surface-hover'
            : 'border-l-transparent'
        }`}
      >
        <div className="flex items-center justify-between gap-2 min-w-0">
          <div className="flex items-center gap-2 min-w-0 flex-1">
            {/* Status dot */}
            <span className="relative flex-shrink-0">
              <span className={`block w-2 h-2 rounded-full ${statusStyle.dot}`} />
              {statusStyle.pulse && (
                <span className={`absolute inset-0 w-2 h-2 rounded-full ${statusStyle.dot} animate-ping opacity-40`} />
              )}
            </span>
            {/* Name */}
            <span className="text-sm font-medium text-theme-primary truncate">{agent.name}</span>
          </div>
          {agent.updated_at && (
            <span className="text-[10px] text-theme-tertiary whitespace-nowrap flex-shrink-0">
              {timeAgo(agent.updated_at)}
            </span>
          )}
        </div>

        {/* Second row: provider/model + execution count */}
        <div className="flex items-center justify-between gap-2 mt-1 pl-4">
          <span className="text-[10px] text-theme-secondary truncate">
            {agent.provider?.name || 'No provider'}{agent.model ? ` · ${agent.model}` : ''}
          </span>
          {executions > 0 && (
            <span className="text-[10px] text-theme-tertiary whitespace-nowrap flex-shrink-0">
              {executions} exec{executions !== 1 ? 's' : ''}
            </span>
          )}
        </div>
      </button>

      {canManage && (
        <div
          className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity z-10"
          onClick={(e) => e.stopPropagation()}
        >
          <DropdownMenu
            trigger={
              <button className="p-1 rounded hover:bg-theme-surface-hover text-theme-tertiary hover:text-theme-primary">
                <MoreHorizontal className="h-3.5 w-3.5" />
              </button>
            }
            items={menuItems}
            align="right"
            width="w-36"
          />
        </div>
      )}
    </div>
  );
};
