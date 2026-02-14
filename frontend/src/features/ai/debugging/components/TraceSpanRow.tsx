import React from 'react';
import {
  ChevronDown,
  ChevronRight,
  Clock,
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
import { Badge } from '@/shared/components/ui/Badge';
import { cn } from '@/shared/utils/cn';

export interface TraceSpan {
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

export const spanTypeIcons: Record<string, React.FC<{ className?: string }>> = {
  root: Layers,
  llm_call: Bot,
  tool_execution: Wrench,
  retrieval: Database,
  generic: Play,
  agent: Bot,
  workflow: Layers,
  mcp: Layers,
};

export const statusConfig: Record<string, { icon: React.FC<{ className?: string }>; color: string; bgColor: string }> = {
  pending: { icon: Clock, color: 'text-theme-muted', bgColor: 'bg-theme-muted/10' },
  running: { icon: Loader2, color: 'text-theme-info', bgColor: 'bg-theme-info/10' },
  completed: { icon: CheckCircle, color: 'text-theme-success', bgColor: 'bg-theme-success/10' },
  failed: { icon: XCircle, color: 'text-theme-danger', bgColor: 'bg-theme-danger/10' },
  cancelled: { icon: AlertCircle, color: 'text-theme-warning', bgColor: 'bg-theme-warning/10' },
};

export const formatDuration = (ms: number | null) => {
  if (ms === null) return '-';
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(2)}s`;
};

export const formatCost = (cost: number) => {
  return `$${cost.toFixed(6)}`;
};

export interface TraceSpanRowProps {
  span: TraceSpan & { children: TraceSpan[] };
  depth?: number;
  expandedSpans: Set<string>;
  selectedSpanId: string | null;
  onToggleExpand: (spanId: string) => void;
  onSelectSpan: (span: TraceSpan) => void;
}

export const TraceSpanRow: React.FC<TraceSpanRowProps> = ({
  span,
  depth = 0,
  expandedSpans,
  selectedSpanId,
  onToggleExpand,
  onSelectSpan,
}) => {
  const hasChildren = span.children.length > 0;
  const isExpanded = expandedSpans.has(span.span_id);
  const isSelected = selectedSpanId === span.span_id;
  const StatusIcon = statusConfig[span.status]?.icon || AlertCircle;
  const SpanIcon = spanTypeIcons[span.type] || Play;

  return (
    <React.Fragment>
      <div
        className={cn(
          'flex items-center gap-2 px-3 py-2 hover:bg-theme-surface cursor-pointer border-b border-theme transition-colors',
          isSelected && 'bg-theme-primary-subtle'
        )}
        onClick={() => onSelectSpan(span)}
        style={{ paddingLeft: `${depth * 24 + 12}px` }}
      >
        <button
          className="w-5 h-5 flex items-center justify-center"
          onClick={(e) => {
            e.stopPropagation();
            onToggleExpand(span.span_id);
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

        <StatusIcon
          className={cn(
            'h-4 w-4',
            statusConfig[span.status]?.color,
            span.status === 'running' && 'animate-spin'
          )}
        />

        <SpanIcon className="h-4 w-4 text-theme-muted" />

        <span className="flex-1 text-sm text-theme-primary truncate">
          {span.name}
        </span>

        <Badge variant="outline" size="sm">
          {span.type}
        </Badge>

        <span className="text-xs text-theme-muted w-16 text-right">
          {formatDuration(span.duration_ms)}
        </span>

        {span.tokens.total > 0 && (
          <span className="text-xs text-theme-muted w-16 text-right">
            {span.tokens.total} tok
          </span>
        )}

        {span.cost > 0 && (
          <span className="text-xs text-theme-muted w-20 text-right">
            {formatCost(span.cost)}
          </span>
        )}
      </div>

      {hasChildren && isExpanded && (
        span.children
          .sort((a, b) => new Date(a.started_at || 0).getTime() - new Date(b.started_at || 0).getTime())
          .map(child => (
            <TraceSpanRow
              key={child.span_id}
              span={child as TraceSpan & { children: TraceSpan[] }}
              depth={depth + 1}
              expandedSpans={expandedSpans}
              selectedSpanId={selectedSpanId}
              onToggleExpand={onToggleExpand}
              onSelectSpan={onSelectSpan}
            />
          ))
      )}
    </React.Fragment>
  );
};
