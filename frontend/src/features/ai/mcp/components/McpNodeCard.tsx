import React from 'react';
import { Bot, Server, Wrench } from 'lucide-react';
import { cn } from '@/shared/utils/cn';

type NodeVariant = 'agent' | 'server' | 'tool';

interface McpNodeCardProps {
  id: string;
  name: string;
  variant: NodeVariant;
  status: string;
  metric?: string;
  metricLabel?: string;
  isSelected: boolean;
  onClick: (id: string) => void;
}

const variantConfig: Record<NodeVariant, {
  icon: React.FC<{ className?: string }>;
  label: string;
}> = {
  agent: { icon: Bot, label: 'Agent' },
  server: { icon: Server, label: 'Server' },
  tool: { icon: Wrench, label: 'Tool' },
};

const statusDotColor: Record<string, string> = {
  active: 'bg-theme-success',
  connected: 'bg-theme-success',
  healthy: 'bg-theme-success',
  inactive: 'bg-theme-muted',
  disconnected: 'bg-theme-warning',
  connecting: 'bg-theme-warning',
  error: 'bg-theme-danger',
};

export const McpNodeCard: React.FC<McpNodeCardProps> = ({
  id,
  name,
  variant,
  status,
  metric,
  metricLabel,
  isSelected,
  onClick,
}) => {
  const config = variantConfig[variant];
  const Icon = config.icon;
  const dotColor = statusDotColor[status] || 'bg-theme-muted';

  return (
    <button
      onClick={() => onClick(id)}
      className={cn(
        'w-full px-3 py-2 rounded-lg border text-left transition-all',
        'hover:bg-theme-surface-hover cursor-pointer',
        isSelected
          ? 'border-theme-interactive-primary bg-theme-interactive-primary/5'
          : 'border-theme-border bg-theme-surface'
      )}
    >
      <div className="flex items-center gap-2 min-w-0">
        <span className={cn('w-2 h-2 rounded-full flex-shrink-0', dotColor)} />
        <Icon className="w-3.5 h-3.5 text-theme-secondary flex-shrink-0" />
        <span className="text-xs font-medium text-theme-primary truncate">
          {name}
        </span>
      </div>
      {metric && (
        <div className="mt-1 pl-[22px]">
          <span className="text-[10px] text-theme-muted">
            {metric}{metricLabel ? ` ${metricLabel}` : ''}
          </span>
        </div>
      )}
    </button>
  );
};

export default McpNodeCard;
