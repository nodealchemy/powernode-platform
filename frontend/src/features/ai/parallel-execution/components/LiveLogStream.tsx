import React, { useRef, useEffect } from 'react';
import type { LogEntry } from '../types';

interface LiveLogStreamProps {
  logs: LogEntry[];
  maxHeight?: number;
}

const LEVEL_COLORS: Record<string, string> = {
  info: 'text-theme-status-info',
  warn: 'text-theme-status-warning',
  error: 'text-theme-status-error',
  debug: 'text-theme-text-tertiary',
};

export const LiveLogStream: React.FC<LiveLogStreamProps> = ({ logs, maxHeight = 300 }) => {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [logs.length]);

  if (logs.length === 0) {
    return (
      <div className="text-center p-4 text-theme-text-secondary text-sm">
        No log entries yet.
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      className="bg-theme-bg-tertiary rounded-lg p-3 overflow-y-auto font-mono text-xs"
      style={{ maxHeight }}
    >
      {logs.map((entry, index) => (
        <div key={index} className="flex gap-2 py-0.5">
          <span className="text-theme-text-tertiary flex-shrink-0">
            {new Date(entry.timestamp).toLocaleTimeString()}
          </span>
          <span className={`flex-shrink-0 uppercase w-12 ${LEVEL_COLORS[entry.level] || 'text-theme-text-secondary'}`}>
            [{entry.level}]
          </span>
          {entry.source && (
            <span className="text-theme-text-secondary flex-shrink-0">[{entry.source}]</span>
          )}
          <span className="text-theme-text-primary break-all">{entry.message}</span>
        </div>
      ))}
    </div>
  );
};
