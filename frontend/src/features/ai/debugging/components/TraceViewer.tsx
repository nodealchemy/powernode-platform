import React, { useState, useMemo } from 'react';
import { Layers } from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import { type TraceSpan, formatDuration, formatCost } from './TraceSpanRow';
import { TraceSpanRow } from './TraceSpanRow';
import { SpanDetailPanel } from './SpanDetailPanel';
import { TraceTimeline } from './TraceTimeline';

interface TraceSummary {
  total_spans: number;
  llm_calls: number;
  tool_executions: number;
  total_tokens: number;
  total_cost: number;
  failed_spans: number;
}

interface TraceData {
  trace_id: string;
  name: string;
  type: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  started_at: string | null;
  completed_at: string | null;
  duration_ms: number | null;
  metadata: Record<string, unknown>;
  error: string | null;
  spans: TraceSpan[];
  summary: TraceSummary;
}

interface TraceViewerProps {
  trace: TraceData;
  className?: string;
}

export const TraceViewer: React.FC<TraceViewerProps> = ({ trace, className }) => {
  const [expandedSpans, setExpandedSpans] = useState<Set<string>>(new Set([trace.spans[0]?.span_id]));
  const [selectedSpan, setSelectedSpan] = useState<TraceSpan | null>(null);
  const [viewMode, setViewMode] = useState<'tree' | 'timeline'>('tree');

  const spanTree = useMemo(() => {
    const spanMap = new Map<string, TraceSpan & { children: TraceSpan[] }>();

    trace.spans.forEach(span => {
      spanMap.set(span.span_id, { ...span, children: [] });
    });

    const roots: (TraceSpan & { children: TraceSpan[] })[] = [];
    spanMap.forEach(span => {
      if (span.parent_span_id && spanMap.has(span.parent_span_id)) {
        spanMap.get(span.parent_span_id)!.children.push(span);
      } else if (!span.parent_span_id) {
        roots.push(span);
      }
    });

    return roots;
  }, [trace.spans]);

  const toggleExpand = (spanId: string) => {
    setExpandedSpans(prev => {
      const next = new Set(prev);
      if (next.has(spanId)) {
        next.delete(spanId);
      } else {
        next.add(spanId);
      }
      return next;
    });
  };

  const traceStartTime = trace.started_at ? new Date(trace.started_at).getTime() : 0;
  const traceDuration = trace.duration_ms || 1;

  return (
    <div className={cn('flex flex-col h-full', className)}>
      <Card className="mb-4">
        <CardHeader
          title={trace.name}
          icon={<Layers className="h-5 w-5" />}
          action={
            <div className="flex items-center gap-2">
              <Badge
                variant={trace.status === 'completed' ? 'success' : trace.status === 'failed' ? 'danger' : 'info'}
              >
                {trace.status}
              </Badge>
              <Badge variant="outline">{trace.type}</Badge>
            </div>
          }
        />
        <CardContent>
          <div className="grid grid-cols-5 gap-4 text-sm">
            <div>
              <span className="text-theme-muted">Duration</span>
              <p className="font-medium text-theme-primary">{formatDuration(trace.duration_ms)}</p>
            </div>
            <div>
              <span className="text-theme-muted">Spans</span>
              <p className="font-medium text-theme-primary">{trace.summary.total_spans}</p>
            </div>
            <div>
              <span className="text-theme-muted">LLM Calls</span>
              <p className="font-medium text-theme-primary">{trace.summary.llm_calls}</p>
            </div>
            <div>
              <span className="text-theme-muted">Total Tokens</span>
              <p className="font-medium text-theme-primary">{trace.summary.total_tokens.toLocaleString()}</p>
            </div>
            <div>
              <span className="text-theme-muted">Total Cost</span>
              <p className="font-medium text-theme-primary">{formatCost(trace.summary.total_cost)}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="flex items-center gap-2 mb-4">
        <Button
          variant={viewMode === 'tree' ? 'primary' : 'outline'}
          size="sm"
          onClick={() => setViewMode('tree')}
        >
          Tree View
        </Button>
        <Button
          variant={viewMode === 'timeline' ? 'primary' : 'outline'}
          size="sm"
          onClick={() => setViewMode('timeline')}
        >
          Timeline
        </Button>
      </div>

      <div className="flex-1 flex gap-4 min-h-0">
        <Card className="flex-1 overflow-hidden">
          <CardContent className="p-0 h-full overflow-auto">
            {viewMode === 'tree' ? (
              <div className="min-w-max">
                <div className="flex items-center gap-2 px-3 py-2 bg-theme-surface border-b border-theme sticky top-0 text-xs text-theme-muted font-medium">
                  <span className="w-5" />
                  <span className="w-4" />
                  <span className="w-4" />
                  <span className="flex-1">Span</span>
                  <span className="w-20">Type</span>
                  <span className="w-16 text-right">Duration</span>
                  <span className="w-16 text-right">Tokens</span>
                  <span className="w-20 text-right">Cost</span>
                </div>
                {spanTree.map(span => (
                  <TraceSpanRow
                    key={span.span_id}
                    span={span}
                    expandedSpans={expandedSpans}
                    selectedSpanId={selectedSpan?.span_id || null}
                    onToggleExpand={toggleExpand}
                    onSelectSpan={setSelectedSpan}
                  />
                ))}
              </div>
            ) : (
              <TraceTimeline
                spans={trace.spans}
                traceStartTime={traceStartTime}
                traceDuration={traceDuration}
              />
            )}
          </CardContent>
        </Card>

        <Card className="w-96 overflow-hidden">
          <CardHeader title="Span Details" />
          <CardContent className="p-0 overflow-auto">
            <SpanDetailPanel selectedSpan={selectedSpan} />
          </CardContent>
        </Card>
      </div>
    </div>
  );
};

export default TraceViewer;
