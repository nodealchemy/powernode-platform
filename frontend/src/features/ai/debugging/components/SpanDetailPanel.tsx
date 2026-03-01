import React from 'react';
import { Clock, DollarSign, Hash, AlertCircle } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { cn } from '@/shared/utils/cn';
import { type TraceSpan, statusConfig, formatDuration, formatCost } from './TraceSpanRow';

interface SpanDetailPanelProps {
  selectedSpan: TraceSpan | null;
}

export const SpanDetailPanel: React.FC<SpanDetailPanelProps> = ({ selectedSpan }) => {
  if (!selectedSpan) {
    return (
      <div className="flex items-center justify-center h-64 text-theme-muted">
        <p className="text-sm">Select a span to view details</p>
      </div>
    );
  }

  const StatusIcon = statusConfig[selectedSpan.status]?.icon || AlertCircle;

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center gap-2">
        <StatusIcon className={cn('h-5 w-5', statusConfig[selectedSpan.status]?.color)} />
        <h3 className="text-lg font-semibold text-theme-primary">{selectedSpan.name}</h3>
        <Badge variant={selectedSpan.status === 'completed' ? 'success' : selectedSpan.status === 'failed' ? 'danger' : 'outline'}>
          {selectedSpan.status}
        </Badge>
      </div>

      <div className="grid grid-cols-4 gap-4">
        <div className="p-3 bg-theme-surface rounded">
          <div className="flex items-center gap-1 text-xs text-theme-muted mb-1">
            <Clock className="h-3 w-3" />
            Duration
          </div>
          <div className="text-lg font-semibold text-theme-primary">
            {formatDuration(selectedSpan.duration_ms)}
          </div>
        </div>
        <div className="p-3 bg-theme-surface rounded">
          <div className="flex items-center gap-1 text-xs text-theme-muted mb-1">
            <Hash className="h-3 w-3" />
            Tokens
          </div>
          <div className="text-lg font-semibold text-theme-primary">
            {selectedSpan.tokens.total}
          </div>
        </div>
        <div className="p-3 bg-theme-surface rounded">
          <div className="flex items-center gap-1 text-xs text-theme-muted mb-1">
            <DollarSign className="h-3 w-3" />
            Cost
          </div>
          <div className="text-lg font-semibold text-theme-primary">
            {formatCost(selectedSpan.cost)}
          </div>
        </div>
        <div className="p-3 bg-theme-surface rounded">
          <div className="text-xs text-theme-muted mb-1">Type</div>
          <div className="text-lg font-semibold text-theme-primary capitalize">
            {selectedSpan.type.replace('_', ' ')}
          </div>
        </div>
      </div>

      {selectedSpan.error && (
        <div className="p-3 bg-theme-danger/10 border border-theme-danger/30 rounded">
          <div className="flex items-center gap-2 text-theme-danger mb-1">
            <AlertCircle className="h-4 w-4" />
            <span className="font-medium">Error</span>
          </div>
          <pre className="text-xs text-theme-danger whitespace-pre-wrap">{selectedSpan.error}</pre>
        </div>
      )}

      <div className="grid grid-cols-2 gap-4">
        {selectedSpan.input && (
          <div>
            <h4 className="text-sm font-medium text-theme-muted mb-2">Input</h4>
            <pre className="text-xs bg-theme-surface p-3 rounded overflow-auto max-h-48">
              {JSON.stringify(selectedSpan.input, null, 2)}
            </pre>
          </div>
        )}
        {selectedSpan.output && (
          <div>
            <h4 className="text-sm font-medium text-theme-muted mb-2">Output</h4>
            <pre className="text-xs bg-theme-surface p-3 rounded overflow-auto max-h-48">
              {JSON.stringify(selectedSpan.output, null, 2)}
            </pre>
          </div>
        )}
      </div>

      {selectedSpan.events.length > 0 && (
        <div>
          <h4 className="text-sm font-medium text-theme-muted mb-2">Events</h4>
          <div className="space-y-2">
            {selectedSpan.events.map((event, i) => (
              <div key={i} className="p-2 bg-theme-surface rounded text-xs">
                <div className="flex items-center justify-between mb-1">
                  <span className="font-medium">{event.name}</span>
                  <span className="text-theme-muted">
                    {new Date(event.timestamp).toLocaleTimeString()}
                  </span>
                </div>
                {Object.keys(event.data).length > 0 && (
                  <pre className="text-theme-muted">{JSON.stringify(event.data, null, 2)}</pre>
                )}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
