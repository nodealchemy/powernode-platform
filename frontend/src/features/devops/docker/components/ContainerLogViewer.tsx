import React, { useEffect, useRef, useState } from 'react';
import type { ContainerLogEntry } from '../types';

interface ContainerLogViewerProps {
  logs: ContainerLogEntry[];
  onTailChange?: (tail: number) => void;
  onSinceChange?: (since: string) => void;
  isLoading?: boolean;
}

export const ContainerLogViewer: React.FC<ContainerLogViewerProps> = ({
  logs,
  onTailChange,
  onSinceChange,
  isLoading = false,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);
  const [tail, setTail] = useState(100);
  const [since, setSince] = useState('');

  useEffect(() => {
    if (autoScroll && containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [logs, autoScroll]);

  const handleScroll = () => {
    if (!containerRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = containerRef.current;
    setAutoScroll(scrollHeight - scrollTop - clientHeight < 50);
  };

  const handleTailChange = (value: number) => {
    setTail(value);
    onTailChange?.(value);
  };

  const handleSinceChange = (value: string) => {
    setSince(value);
    onSinceChange?.(value);
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-4 flex-wrap">
        <div className="flex items-center gap-2">
          <label className="text-xs text-theme-secondary">Tail:</label>
          <select
            className="input-theme text-xs py-1"
            value={tail}
            onChange={(e) => handleTailChange(Number(e.target.value))}
          >
            <option value={50}>50 lines</option>
            <option value={100}>100 lines</option>
            <option value={500}>500 lines</option>
            <option value={1000}>1000 lines</option>
          </select>
        </div>
        <div className="flex items-center gap-2">
          <label className="text-xs text-theme-secondary">Since:</label>
          <select
            className="input-theme text-xs py-1"
            value={since}
            onChange={(e) => handleSinceChange(e.target.value)}
          >
            <option value="">All time</option>
            <option value="5m">5 minutes</option>
            <option value="15m">15 minutes</option>
            <option value="1h">1 hour</option>
            <option value="6h">6 hours</option>
            <option value="24h">24 hours</option>
          </select>
        </div>
        <div className="flex items-center gap-2 ml-auto">
          <label className="flex items-center gap-1.5 text-xs text-theme-secondary cursor-pointer">
            <input
              type="checkbox"
              checked={autoScroll}
              onChange={(e) => setAutoScroll(e.target.checked)}
              className="rounded border-theme text-theme-interactive-primary"
            />
            Auto-scroll
          </label>
        </div>
      </div>

      <div
        ref={containerRef}
        onScroll={handleScroll}
        className="bg-theme-bg-surface rounded-lg border border-theme overflow-auto max-h-[500px] custom-scrollbar"
      >
        {isLoading ? (
          <div className="p-4 text-center text-xs text-theme-tertiary animate-pulse">
            Loading logs...
          </div>
        ) : logs.length === 0 ? (
          <div className="p-4 text-center text-xs text-theme-tertiary">
            No logs available
          </div>
        ) : (
          <pre className="p-3 text-xs font-mono leading-relaxed">
            {logs.map((entry, i) => (
              <div key={i} className={`hover:bg-theme-surface-hover ${entry.stream === 'stderr' ? 'text-theme-error' : 'text-theme-primary'}`}>
                {entry.timestamp && (
                  <span className="text-theme-tertiary mr-2">{new Date(entry.timestamp).toLocaleTimeString()}</span>
                )}
                <span>{entry.message}</span>
              </div>
            ))}
          </pre>
        )}
      </div>
    </div>
  );
};
