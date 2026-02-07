import React, { useState } from 'react';
import {
  Brain,
  Lightbulb,
  Activity,
  Clock,
  CheckCircle,
  XCircle,
  Edit2,
  Trash2,
  Copy,
  ChevronDown,
  ChevronUp,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { cn } from '@/shared/utils/cn';
import { formatDateTime } from '@/shared/utils/formatters';
import type { MemoryEntry, MemoryType } from '@/shared/services/ai/types/memory-types';

interface MemoryEntryCardProps {
  memory: MemoryEntry;
  onEdit?: (memory: MemoryEntry) => void;
  onDelete?: (memory: MemoryEntry) => void;
  className?: string;
}

const memoryTypeConfig: Record<
  MemoryType,
  { icon: React.FC<{ className?: string }>; bgColor: string; textColor: string; label: string }
> = {
  factual: {
    icon: Brain,
    bgColor: 'bg-theme-info/10',
    textColor: 'text-theme-info',
    label: 'Factual',
  },
  experiential: {
    icon: Lightbulb,
    bgColor: 'bg-theme-warning/10',
    textColor: 'text-theme-warning',
    label: 'Experiential',
  },
  working: {
    icon: Activity,
    bgColor: 'bg-theme-success/10',
    textColor: 'text-theme-success',
    label: 'Working',
  },
};

export const MemoryEntryCard: React.FC<MemoryEntryCardProps> = ({
  memory,
  onEdit,
  onDelete,
  className,
}) => {
  const [expanded, setExpanded] = useState(false);
  const { addNotification } = useNotifications();

  const config = memoryTypeConfig[memory.memory_type];
  const TypeIcon = config.icon;

  const getContentPreview = (): string => {
    if (memory.content_text) return memory.content_text;
    if (typeof memory.content === 'object' && memory.content !== null) {
      if ('text' in memory.content && typeof memory.content.text === 'string') {
        return memory.content.text;
      }
      return JSON.stringify(memory.content);
    }
    return String(memory.content);
  };

  const copyContent = () => {
    navigator.clipboard.writeText(getContentPreview());
    addNotification({ type: 'success', title: 'Copied', message: 'Content copied to clipboard' });
  };

  return (
    <Card className={cn('hover:border-theme-primary/30 transition-colors', className)}>
      <CardContent className="p-4">
        {/* Header */}
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-start gap-3 flex-1 min-w-0">
            <div className={cn('p-2 rounded-lg shrink-0', config.bgColor)}>
              <TypeIcon className={cn('h-4 w-4', config.textColor)} />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="font-mono text-sm font-medium text-theme-primary">
                  {memory.entry_key}
                </span>
                <Badge variant="outline" size="sm" className={config.textColor}>
                  {config.label}
                </Badge>
                {memory.entry_type && (
                  <Badge variant="outline" size="sm">
                    {memory.entry_type}
                  </Badge>
                )}
                {memory.outcome_success === true && (
                  <CheckCircle className="h-4 w-4 text-theme-success" />
                )}
                {memory.outcome_success === false && (
                  <XCircle className="h-4 w-4 text-theme-danger" />
                )}
              </div>
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-center gap-1 shrink-0">
            <Button variant="ghost" size="sm" onClick={copyContent}>
              <Copy className="h-4 w-4" />
            </Button>
            {onEdit && (
              <Button variant="ghost" size="sm" onClick={() => onEdit(memory)}>
                <Edit2 className="h-4 w-4" />
              </Button>
            )}
            {onDelete && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onDelete(memory)}
                className="text-theme-danger hover:text-theme-danger"
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            )}
          </div>
        </div>

        {/* Content preview */}
        <div className="mt-3">
          <p
            className={cn(
              'text-sm text-theme-secondary',
              !expanded && 'line-clamp-2'
            )}
          >
            {getContentPreview()}
          </p>
        </div>

        {/* Metadata */}
        <div className="flex items-center gap-4 mt-3 text-xs text-theme-muted">
          <span className="flex items-center gap-1">
            <Clock className="h-3 w-3" />
            {formatDateTime(memory.created_at)}
          </span>
          <span>Importance: {Math.round(memory.importance_score * 100)}%</span>
          <span>Confidence: {Math.round(memory.confidence_score * 100)}%</span>
          {memory.access_count > 0 && <span>{memory.access_count} accesses</span>}
        </div>

        {/* Tags */}
        {memory.context_tags?.length > 0 && (
          <div className="flex flex-wrap gap-1 mt-2">
            {memory.context_tags.slice(0, expanded ? undefined : 5).map((tag) => (
              <Badge key={tag} variant="outline" size="sm">
                {tag}
              </Badge>
            ))}
            {!expanded && memory.context_tags.length > 5 && (
              <Badge variant="outline" size="sm">
                +{memory.context_tags.length - 5}
              </Badge>
            )}
          </div>
        )}

        {/* Expand toggle */}
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setExpanded(!expanded)}
          className="mt-3 w-full justify-center"
        >
          {expanded ? (
            <>
              <ChevronUp className="h-4 w-4 mr-1" />
              Show Less
            </>
          ) : (
            <>
              <ChevronDown className="h-4 w-4 mr-1" />
              Show More
            </>
          )}
        </Button>

        {/* Expanded content */}
        {expanded && (
          <div className="mt-4 pt-4 border-t border-theme space-y-4">
            {/* Full content */}
            <div>
              <h4 className="text-xs font-medium text-theme-secondary mb-2">Full Content</h4>
              <pre className="bg-theme-surface-dark p-3 rounded-lg text-xs overflow-x-auto">
                <code className="text-theme-primary">
                  {JSON.stringify(memory.content, null, 2)}
                </code>
              </pre>
            </div>

            {/* Task context */}
            {memory.task_context && Object.keys(memory.task_context).length > 0 && (
              <div>
                <h4 className="text-xs font-medium text-theme-secondary mb-2">Task Context</h4>
                <pre className="bg-theme-surface-dark p-3 rounded-lg text-xs overflow-x-auto">
                  <code className="text-theme-primary">
                    {JSON.stringify(memory.task_context, null, 2)}
                  </code>
                </pre>
              </div>
            )}

            {/* Metadata */}
            {memory.metadata && Object.keys(memory.metadata).length > 0 && (
              <div>
                <h4 className="text-xs font-medium text-theme-secondary mb-2">Metadata</h4>
                <pre className="bg-theme-surface-dark p-3 rounded-lg text-xs overflow-x-auto">
                  <code className="text-theme-primary">
                    {JSON.stringify(memory.metadata, null, 2)}
                  </code>
                </pre>
              </div>
            )}

            {/* Additional details */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div>
                <span className="text-xs text-theme-muted">Source Type</span>
                <div className="text-theme-primary">{memory.source_type || 'N/A'}</div>
              </div>
              <div>
                <span className="text-xs text-theme-muted">Version</span>
                <div className="text-theme-primary">{memory.version}</div>
              </div>
              <div>
                <span className="text-xs text-theme-muted">Decay Rate</span>
                <div className="text-theme-primary">{memory.decay_rate}</div>
              </div>
              <div>
                <span className="text-xs text-theme-muted">Last Accessed</span>
                <div className="text-theme-primary">
                  {memory.last_accessed_at
                    ? formatDateTime(memory.last_accessed_at)
                    : 'Never'}
                </div>
              </div>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default MemoryEntryCard;
