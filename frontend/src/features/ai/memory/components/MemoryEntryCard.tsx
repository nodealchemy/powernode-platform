import React, { useState } from 'react';
import { Trash2, ChevronDown, ChevronUp, Clock, Hash } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import type { MemoryEntry } from '../types/memory';

interface MemoryEntryCardProps {
  entry: MemoryEntry;
  onDelete?: (entry: MemoryEntry) => void;
  className?: string;
}

const TIER_BADGE_VARIANT: Record<string, 'info' | 'warning' | 'success' | 'default'> = {
  working: 'warning',
  short_term: 'info',
  long_term: 'success',
  shared: 'default',
};

function formatValue(value: unknown): string {
  if (typeof value === 'string') return value;
  if (value === null || value === undefined) return 'null';
  return JSON.stringify(value, null, 2);
}

function isExpired(expiresAt?: string): boolean {
  if (!expiresAt) return false;
  return new Date(expiresAt) < new Date();
}

export const MemoryEntryCard: React.FC<MemoryEntryCardProps> = ({
  entry,
  onDelete,
  className,
}) => {
  const [expanded, setExpanded] = useState(false);
  const valueStr = formatValue(entry.value);
  const isObject = typeof entry.value === 'object' && entry.value !== null;
  const expired = isExpired(entry.expires_at);

  return (
    <Card className={cn('hover:border-theme-primary/30 transition-colors', expired && 'opacity-60', className)}>
      <CardContent className="p-4">
        {/* Header */}
        <div className="flex items-start justify-between gap-3">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="font-mono text-sm font-medium text-theme-primary">
                {entry.key}
              </span>
              <Badge variant={TIER_BADGE_VARIANT[entry.tier] || 'default'} size="sm">
                {entry.tier.replace('_', ' ')}
              </Badge>
              {entry.memory_type && (
                <Badge variant="outline" size="sm">
                  {entry.memory_type}
                </Badge>
              )}
              {expired && (
                <Badge variant="danger" size="sm">expired</Badge>
              )}
            </div>

            {/* Value preview */}
            <pre
              className={cn(
                'mt-2 text-sm text-theme-secondary bg-theme-surface rounded p-2 overflow-x-auto',
                !expanded && 'max-h-16 overflow-hidden'
              )}
            >
              <code>{isObject && !expanded ? JSON.stringify(entry.value) : valueStr}</code>
            </pre>
          </div>

          {/* Delete action */}
          {onDelete && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => onDelete(entry)}
              className="text-theme-danger hover:text-theme-danger shrink-0"
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          )}
        </div>

        {/* Metadata row */}
        <div className="flex items-center gap-4 mt-3 text-xs text-theme-muted">
          {entry.access_count !== undefined && entry.access_count > 0 && (
            <span className="flex items-center gap-1">
              <Hash className="h-3 w-3" />
              {entry.access_count} accesses
            </span>
          )}
          {entry.expires_at && (
            <span className="flex items-center gap-1">
              <Clock className="h-3 w-3" />
              Expires: {new Date(entry.expires_at).toLocaleString()}
            </span>
          )}
          {entry.created_at && (
            <span className="flex items-center gap-1">
              <Clock className="h-3 w-3" />
              {new Date(entry.created_at).toLocaleString()}
            </span>
          )}
          {entry.session_id && (
            <span className="font-mono">session: {entry.session_id.substring(0, 8)}...</span>
          )}
        </div>

        {/* Expand toggle for objects */}
        {isObject && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setExpanded(!expanded)}
            className="mt-2 w-full justify-center"
          >
            {expanded ? (
              <>
                <ChevronUp className="h-4 w-4 mr-1" />
                Collapse
              </>
            ) : (
              <>
                <ChevronDown className="h-4 w-4 mr-1" />
                Expand JSON
              </>
            )}
          </Button>
        )}
      </CardContent>
    </Card>
  );
};
