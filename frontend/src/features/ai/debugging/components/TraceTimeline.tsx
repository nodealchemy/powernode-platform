import React from 'react';
import { AlertCircle } from 'lucide-react';
import { cn } from '@/shared/utils/cn';
import { type TraceSpan, statusConfig, formatDuration } from './TraceSpanRow';

interface TraceTimelineProps {
  spans: TraceSpan[];
  traceStartTime: number;
  traceDuration: number;
}

export const TraceTimeline: React.FC<TraceTimelineProps> = ({
  spans,
  traceStartTime,
  traceDuration,
}) => (
  <div className="space-y-1 p-4">
    {spans.map(span => {
      const spanStartTime = span.started_at ? new Date(span.started_at).getTime() : traceStartTime;
      const startOffset = ((spanStartTime - traceStartTime) / traceDuration) * 100;
      const width = Math.max(((span.duration_ms || 0) / traceDuration) * 100, 1);
      const StatusIcon = statusConfig[span.status]?.icon || AlertCircle;

      return (
        <div
          key={span.span_id}
          className="flex items-center gap-2 py-1"
          style={{ paddingLeft: `${span.depth * 16}px` }}
        >
          <div className="w-32 text-xs text-theme-muted truncate">{span.name}</div>
          <div className="flex-1 relative h-6 bg-theme-surface rounded">
            <div
              className={cn(
                'absolute h-full rounded flex items-center px-1',
                statusConfig[span.status]?.bgColor
              )}
              style={{
                left: `${startOffset}%`,
                width: `${Math.max(width, 2)}%`,
              }}
            >
              <StatusIcon className={cn('h-3 w-3', statusConfig[span.status]?.color)} />
            </div>
          </div>
          <div className="w-16 text-xs text-theme-muted text-right">
            {formatDuration(span.duration_ms)}
          </div>
        </div>
      );
    })}
  </div>
);
