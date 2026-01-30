import React, { useState, useMemo } from 'react';
import {
  ChevronDown,
  ChevronRight,
  Clock,
  DollarSign,
  Hash,
  AlertCircle,
  CheckCircle,
  XCircle,
  Loader2,
  Bot,
  Wrench,
  Database,
  Layers,
  Play
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';

// Types
interface TraceSpan {
  id: string;
  span_id: string;
  name: string;
  type: string;
  parent_span_id: string | null;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  started_at: string | null;
  completed_at: string | null;
  duration_ms: number | null;
  input: Record<string, unknown> | null;
  output: Record<string, unknown> | null;
  error: string | null;
  tokens: {
    prompt: number;
    completion: number;
    total: number;
  };
  cost: number;
  events: Array<{
    name: string;
    data: Record<string, unknown>;
    timestamp: string;
  }>;
  metadata: Record<string, unknown>;
  depth: number;
}

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

// Span type icons
const spanTypeIcons: Record<string, React.FC<{ className?: string }>> = {
  root: Layers,
  llm_call: Bot,
  tool_execution: Wrench,
  retrieval: Database,
  generic: Play,
  agent: Bot,
  workflow: Layers,
  mcp: Layers,
};

// Status icons and colors
const statusConfig: Record<string, { icon: React.FC<{ className?: string }>; color: string; bgColor: string }> = {
  pending: { icon: Clock, color: 'text-theme-muted', bgColor: 'bg-theme-muted/10' },
  running: { icon: Loader2, color: 'text-theme-info', bgColor: 'bg-theme-info/10' },
  completed: { icon: CheckCircle, color: 'text-theme-success', bgColor: 'bg-theme-success/10' },
  failed: { icon: XCircle, color: 'text-theme-danger', bgColor: 'bg-theme-danger/10' },
  cancelled: { icon: AlertCircle, color: 'text-theme-warning', bgColor: 'bg-theme-warning/10' },
};

/**
 * TraceViewer - LangSmith-style execution trace visualization
 *
 * Features:
 * - Hierarchical span tree view
 * - Timeline visualization
 * - Detailed span inspection
 * - Token/cost tracking
 */
export const TraceViewer: React.FC<TraceViewerProps> = ({ trace, className }) => {
  const [expandedSpans, setExpandedSpans] = useState<Set<string>>(new Set([trace.spans[0]?.span_id]));
  const [selectedSpan, setSelectedSpan] = useState<TraceSpan | null>(null);
  const [viewMode, setViewMode] = useState<'tree' | 'timeline'>('tree');

  // Build span tree
  const spanTree = useMemo(() => {
    const spanMap = new Map<string, TraceSpan & { children: TraceSpan[] }>();

    // Initialize all spans
    trace.spans.forEach(span => {
      spanMap.set(span.span_id, { ...span, children: [] });
    });

    // Build parent-child relationships
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

  const formatDuration = (ms: number | null) => {
    if (ms === null) return '-';
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  const formatCost = (cost: number) => {
    return `$${cost.toFixed(6)}`;
  };

  const renderSpanRow = (span: TraceSpan & { children: TraceSpan[] }, depth: number = 0) => {
    const hasChildren = span.children.length > 0;
    const isExpanded = expandedSpans.has(span.span_id);
    const isSelected = selectedSpan?.span_id === span.span_id;
    const StatusIcon = statusConfig[span.status]?.icon || AlertCircle;
    const SpanIcon = spanTypeIcons[span.type] || Play;

    return (
      <React.Fragment key={span.span_id}>
        <div
          className={cn(
            'flex items-center gap-2 px-3 py-2 hover:bg-theme-surface cursor-pointer border-b border-theme transition-colors',
            isSelected && 'bg-theme-primary-subtle'
          )}
          onClick={() => setSelectedSpan(span)}
          style={{ paddingLeft: `${depth * 24 + 12}px` }}
        >
          {/* Expand/collapse button */}
          <button
            className="w-5 h-5 flex items-center justify-center"
            onClick={(e) => {
              e.stopPropagation();
              toggleExpand(span.span_id);
            }}
          >
            {hasChildren ? (
              isExpanded ? (
                <ChevronDown className="h-4 w-4 text-theme-muted" />
              ) : (
                <ChevronRight className="h-4 w-4 text-theme-muted" />
              )
            ) : (
              <span className="w-4" />
            )}
          </button>

          {/* Status icon */}
          <StatusIcon
            className={cn(
              'h-4 w-4',
              statusConfig[span.status]?.color,
              span.status === 'running' && 'animate-spin'
            )}
          />

          {/* Span type icon */}
          <SpanIcon className="h-4 w-4 text-theme-muted" />

          {/* Span name */}
          <span className="flex-1 text-sm text-theme-primary truncate">
            {span.name}
          </span>

          {/* Type badge */}
          <Badge variant="outline" size="sm">
            {span.type}
          </Badge>

          {/* Duration */}
          <span className="text-xs text-theme-muted w-16 text-right">
            {formatDuration(span.duration_ms)}
          </span>

          {/* Tokens */}
          {span.tokens.total > 0 && (
            <span className="text-xs text-theme-muted w-16 text-right">
              {span.tokens.total} tok
            </span>
          )}

          {/* Cost */}
          {span.cost > 0 && (
            <span className="text-xs text-theme-muted w-20 text-right">
              {formatCost(span.cost)}
            </span>
          )}
        </div>

        {/* Children */}
        {hasChildren && isExpanded && (
          span.children
            .sort((a, b) => new Date(a.started_at || 0).getTime() - new Date(b.started_at || 0).getTime())
            .map(child => renderSpanRow(child as TraceSpan & { children: TraceSpan[] }, depth + 1))
        )}
      </React.Fragment>
    );
  };

  const renderTimeline = () => {
    const traceStartTime = trace.started_at ? new Date(trace.started_at).getTime() : 0;
    const traceDuration = trace.duration_ms || 1;

    return (
      <div className="space-y-1 p-4">
        {trace.spans.map(span => {
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
  };

  const renderSpanDetails = () => {
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
        {/* Header */}
        <div className="flex items-center gap-2">
          <StatusIcon className={cn('h-5 w-5', statusConfig[selectedSpan.status]?.color)} />
          <h3 className="text-lg font-semibold text-theme-primary">{selectedSpan.name}</h3>
          <Badge variant={selectedSpan.status === 'completed' ? 'success' : selectedSpan.status === 'failed' ? 'danger' : 'outline'}>
            {selectedSpan.status}
          </Badge>
        </div>

        {/* Metrics */}
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

        {/* Error */}
        {selectedSpan.error && (
          <div className="p-3 bg-theme-danger/10 border border-theme-danger/30 rounded">
            <div className="flex items-center gap-2 text-theme-danger mb-1">
              <AlertCircle className="h-4 w-4" />
              <span className="font-medium">Error</span>
            </div>
            <pre className="text-xs text-theme-danger whitespace-pre-wrap">{selectedSpan.error}</pre>
          </div>
        )}

        {/* Input/Output */}
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

        {/* Events */}
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

  return (
    <div className={cn('flex flex-col h-full', className)}>
      {/* Header */}
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

      {/* View mode toggle */}
      <div className="flex items-center gap-2 mb-4">
        <Button
          variant={viewMode === 'tree' ? 'default' : 'outline'}
          size="sm"
          onClick={() => setViewMode('tree')}
        >
          Tree View
        </Button>
        <Button
          variant={viewMode === 'timeline' ? 'default' : 'outline'}
          size="sm"
          onClick={() => setViewMode('timeline')}
        >
          Timeline
        </Button>
      </div>

      {/* Main content */}
      <div className="flex-1 flex gap-4 min-h-0">
        {/* Span list/timeline */}
        <Card className="flex-1 overflow-hidden">
          <CardContent className="p-0 h-full overflow-auto">
            {viewMode === 'tree' ? (
              <div className="min-w-max">
                {/* Header row */}
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
                {/* Span rows */}
                {spanTree.map(span => renderSpanRow(span))}
              </div>
            ) : (
              renderTimeline()
            )}
          </CardContent>
        </Card>

        {/* Span details */}
        <Card className="w-96 overflow-hidden">
          <CardHeader title="Span Details" />
          <CardContent className="p-0 overflow-auto">
            {renderSpanDetails()}
          </CardContent>
        </Card>
      </div>
    </div>
  );
};

export default TraceViewer;
