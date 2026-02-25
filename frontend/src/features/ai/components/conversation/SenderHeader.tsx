import React from 'react';
import { AgentBadge, getAgentNameColorClass } from './AgentBadge';

interface SenderHeaderProps {
  name: string;
  agentType?: string;
  timestamp: string;
  isEdited?: boolean;
  /** Timestamp formatter — defaults to HH:MM format */
  formatTimestamp?: (ts: string) => string;
}

function defaultFormatTime(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

/**
 * Renders a consistent sender name + agent badge + timestamp header.
 * Shared between MessageList (full conversation) and MessageThread.
 */
export const SenderHeader: React.FC<SenderHeaderProps> = ({
  name,
  agentType,
  timestamp,
  isEdited,
  formatTimestamp: formatFn = defaultFormatTime,
}) => {
  return (
    <div className="flex items-center gap-2 mb-0.5 flex-row flex-wrap">
      <span className={`text-sm font-semibold ${getAgentNameColorClass(agentType)}`}>
        {name}
      </span>
      <AgentBadge agentType={agentType} />
      <span className="text-xs text-theme-secondary">
        {formatFn(timestamp)}
      </span>
      {isEdited && (
        <span className="text-[10px] text-theme-text-tertiary italic">(edited)</span>
      )}
    </div>
  );
};
