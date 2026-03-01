import React, { useRef, useEffect, useState, useCallback } from 'react';
import { Badge } from '@/shared/components/ui/Badge';
import { cn } from '@/shared/utils/cn';

export interface ToolLogEntry {
  id: string;
  timestamp: string;
  serverName: string;
  toolName: string;
  status: 'completed' | 'failed' | 'running' | 'pending';
  durationMs?: number;
}

interface McpToolLogProps {
  entries: ToolLogEntry[];
  className?: string;
}

const statusBadge: Record<string, { variant: 'success' | 'danger' | 'warning' | 'outline'; label: string }> = {
  completed: { variant: 'success', label: 'OK' },
  failed: { variant: 'danger', label: 'Fail' },
  running: { variant: 'warning', label: 'Run' },
  pending: { variant: 'outline', label: 'Wait' },
};

const MAX_ENTRIES = 50;

export const McpToolLog: React.FC<McpToolLogProps> = ({ entries, className }) => {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);

  const handleScroll = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    const isNearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
    setAutoScroll(isNearBottom);
  }, []);

  useEffect(() => {
    if (autoScroll && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [entries.length, autoScroll]);

  const displayEntries = entries.slice(-MAX_ENTRIES);

  const formatTime = (ts: string) => {
    try {
      return new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    } catch {
      return ts;
    }
  };

  const formatDuration = (ms?: number) => {
    if (ms === undefined) return '--';
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(1)}s`;
  };

  return (
    <div className={cn('flex flex-col border-t border-theme', className)}>
      <div className="flex items-center justify-between px-3 py-1.5 bg-theme-surface border-b border-theme">
        <span className="text-xs font-medium text-theme-secondary">Tool Log</span>
        <span className="text-[10px] text-theme-muted">
          {displayEntries.length} entries
        </span>
      </div>
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className="flex-1 overflow-y-auto"
        style={{ maxHeight: 160 }}
      >
        {displayEntries.length === 0 ? (
          <div className="px-3 py-4 text-center text-xs text-theme-muted">
            No tool executions yet
          </div>
        ) : (
          <table className="w-full text-xs">
            <thead className="sticky top-0 bg-theme-surface">
              <tr className="text-theme-muted">
                <th className="text-left px-3 py-1 font-normal">Time</th>
                <th className="text-left px-2 py-1 font-normal">Server</th>
                <th className="text-left px-2 py-1 font-normal">Tool</th>
                <th className="text-left px-2 py-1 font-normal">Status</th>
                <th className="text-right px-3 py-1 font-normal">Duration</th>
              </tr>
            </thead>
            <tbody>
              {displayEntries.map((entry) => {
                const badge = statusBadge[entry.status] || statusBadge.pending;
                return (
                  <tr
                    key={entry.id}
                    className="border-t border-theme-border/50 hover:bg-theme-surface-hover transition-colors"
                  >
                    <td className="px-3 py-1 text-theme-muted whitespace-nowrap">
                      {formatTime(entry.timestamp)}
                    </td>
                    <td className="px-2 py-1 text-theme-secondary truncate max-w-[120px]">
                      {entry.serverName}
                    </td>
                    <td className="px-2 py-1 text-theme-primary truncate max-w-[150px] font-medium">
                      {entry.toolName}
                    </td>
                    <td className="px-2 py-1">
                      <Badge variant={badge.variant} size="xs">{badge.label}</Badge>
                    </td>
                    <td className="px-3 py-1 text-right text-theme-muted whitespace-nowrap">
                      {formatDuration(entry.durationMs)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
};

export default McpToolLog;
