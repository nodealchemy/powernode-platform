import React, { useState, useMemo } from 'react';
import { BookOpen, Tag, Globe, Lock, Sparkles, ChevronUp, ChevronDown } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import type { SharedKnowledgeEntry } from '../types/memory';

interface SharedKnowledgeListProps {
  entries: SharedKnowledgeEntry[];
  loading?: boolean;
  className?: string;
}

const CONTENT_TYPE_VARIANT: Record<string, 'info' | 'success' | 'warning' | 'default'> = {
  document: 'info',
  code: 'success',
  config: 'warning',
};

type SortField = 'title' | 'quality_score' | 'usage_count';
type SortDirection = 'asc' | 'desc';

function SortIcon({ field, activeField, direction }: { field: SortField; activeField: SortField; direction: SortDirection }) {
  if (field !== activeField) {
    return <ChevronDown className="h-3 w-3 text-theme-muted/40 inline ml-0.5" />;
  }
  return direction === 'asc'
    ? <ChevronUp className="h-3 w-3 text-theme-primary inline ml-0.5" />
    : <ChevronDown className="h-3 w-3 text-theme-primary inline ml-0.5" />;
}

export const SharedKnowledgeList: React.FC<SharedKnowledgeListProps> = ({
  entries,
  loading,
  className,
}) => {
  const [contentTypeFilter, setContentTypeFilter] = useState<string>('');
  const [sortField, setSortField] = useState<SortField>('title');
  const [sortDirection, setSortDirection] = useState<SortDirection>('asc');

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDirection((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortField(field);
      setSortDirection(field === 'title' ? 'asc' : 'desc');
    }
  };

  const displayEntries = useMemo(() => {
    let filtered = entries;
    if (contentTypeFilter) {
      filtered = filtered.filter((e) => e.content_type === contentTypeFilter);
    }
    return [...filtered].sort((a, b) => {
      const dir = sortDirection === 'asc' ? 1 : -1;
      switch (sortField) {
        case 'quality_score':
          return ((a.quality_score ?? 0) - (b.quality_score ?? 0)) * dir;
        case 'usage_count':
          return (a.usage_count - b.usage_count) * dir;
        case 'title':
        default:
          return a.title.localeCompare(b.title) * dir;
      }
    });
  }, [entries, contentTypeFilter, sortField, sortDirection]);

  if (loading) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
        </CardContent>
      </Card>
    );
  }

  if (entries.length === 0) {
    return (
      <EmptyState
        icon={BookOpen}
        title="No shared knowledge"
        description="Shared knowledge entries will appear here as agents learn and share information"
      />
    );
  }

  // Collect unique content types for the filter dropdown
  const contentTypes = [...new Set(entries.map((e) => e.content_type))].sort();

  return (
    <Card className={className}>
      <CardHeader
        title={`Shared Knowledge (${displayEntries.length}${contentTypeFilter ? ` of ${entries.length}` : ''})`}
      />
      <CardContent>
        {/* Filter bar */}
        <div className="flex items-center gap-3 mb-4">
          <Select
            value={contentTypeFilter}
            onChange={(value) => setContentTypeFilter(value)}
            className="w-40"
          >
            <option value="">All Types</option>
            {contentTypes.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </Select>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-theme">
                <th
                  className="text-left py-2 px-3 text-theme-secondary font-medium cursor-pointer select-none hover:text-theme-primary"
                  onClick={() => handleSort('title')}
                >
                  Title
                  <SortIcon field="title" activeField={sortField} direction={sortDirection} />
                </th>
                <th className="text-left py-2 px-3 text-theme-secondary font-medium">Type</th>
                <th className="text-left py-2 px-3 text-theme-secondary font-medium">Access</th>
                <th className="text-left py-2 px-3 text-theme-secondary font-medium">Tags</th>
                <th
                  className="text-right py-2 px-3 text-theme-secondary font-medium cursor-pointer select-none hover:text-theme-primary"
                  onClick={() => handleSort('quality_score')}
                >
                  Quality
                  <SortIcon field="quality_score" activeField={sortField} direction={sortDirection} />
                </th>
                <th
                  className="text-right py-2 px-3 text-theme-secondary font-medium cursor-pointer select-none hover:text-theme-primary"
                  onClick={() => handleSort('usage_count')}
                >
                  Usage
                  <SortIcon field="usage_count" activeField={sortField} direction={sortDirection} />
                </th>
                <th className="text-center py-2 px-3 text-theme-secondary font-medium">Embedding</th>
              </tr>
            </thead>
            <tbody>
              {displayEntries.map((entry) => (
                <tr
                  key={entry.id}
                  className="border-b border-theme last:border-b-0 hover:bg-theme-surface transition-colors"
                >
                  <td className="py-3 px-3">
                    <div className="font-medium text-theme-primary">{entry.title}</div>
                    <p className="text-xs text-theme-muted mt-0.5 line-clamp-1">{entry.content}</p>
                  </td>
                  <td className="py-3 px-3">
                    <Badge
                      variant={CONTENT_TYPE_VARIANT[entry.content_type] || 'default'}
                      size="sm"
                    >
                      {entry.content_type}
                    </Badge>
                  </td>
                  <td className="py-3 px-3">
                    {entry.access_level === 'public' ? (
                      <span className="flex items-center gap-1 text-theme-success text-xs">
                        <Globe className="h-3 w-3" />
                        Public
                      </span>
                    ) : (
                      <span className="flex items-center gap-1 text-theme-warning text-xs">
                        <Lock className="h-3 w-3" />
                        {entry.access_level}
                      </span>
                    )}
                  </td>
                  <td className="py-3 px-3">
                    <div className="flex flex-wrap gap-1">
                      {entry.tags.slice(0, 3).map((tag) => (
                        <span
                          key={tag}
                          className="inline-flex items-center gap-0.5 px-1.5 py-0.5 text-xs rounded bg-theme-surface text-theme-muted"
                        >
                          <Tag className="h-2.5 w-2.5" />
                          {tag}
                        </span>
                      ))}
                      {entry.tags.length > 3 && (
                        <span className="text-xs text-theme-muted">+{entry.tags.length - 3}</span>
                      )}
                    </div>
                  </td>
                  <td className="py-3 px-3 text-right">
                    {entry.quality_score !== undefined && entry.quality_score !== null ? (
                      <span className="text-theme-primary font-medium">
                        {Math.round(entry.quality_score * 100)}%
                      </span>
                    ) : (
                      <span className="text-theme-muted">-</span>
                    )}
                  </td>
                  <td className="py-3 px-3 text-right">
                    <Badge variant="outline" size="sm">{entry.usage_count}</Badge>
                  </td>
                  <td className="py-3 px-3 text-center">
                    {entry.has_embedding ? (
                      <Sparkles className="h-4 w-4 text-theme-success mx-auto" />
                    ) : (
                      <span className="text-theme-muted text-xs">-</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  );
};
