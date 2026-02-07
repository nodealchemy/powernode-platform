import React, { useRef, useEffect } from 'react';
import { RefreshCw } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import type { ServiceLogEntry } from '../types';

interface SwarmLogViewerProps {
  logs: ServiceLogEntry[];
  isLoading: boolean;
  onRefresh: () => void;
}

export const SwarmLogViewer: React.FC<SwarmLogViewerProps> = ({ logs, isLoading, onRefresh }) => {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [logs]);

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">{logs.length} log entries</span>
        <Button size="xs" variant="ghost" onClick={onRefresh} loading={isLoading}>
          {!isLoading && <RefreshCw className="w-3.5 h-3.5 mr-1" />} Refresh
        </Button>
      </div>

      <div
        ref={containerRef}
        className="bg-theme-surface rounded-lg border border-theme p-4 font-mono text-xs leading-relaxed max-h-[500px] overflow-y-auto"
      >
        {logs.length === 0 ? (
          <p className="text-theme-tertiary">No logs available.</p>
        ) : (
          logs.map((entry, i) => (
            <div key={i} className="flex gap-2 hover:bg-theme-surface-hover rounded px-1">
              <span className="text-theme-tertiary flex-shrink-0 select-none">
                {entry.timestamp ? new Date(entry.timestamp).toLocaleTimeString() : ''}
              </span>
              <span className={entry.stream === 'stderr' ? 'text-theme-error' : 'text-theme-primary'}>
                {entry.message}
              </span>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
