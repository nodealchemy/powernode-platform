import React from 'react';
import { BookOpen, Tag, Globe, Lock, Sparkles } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
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

export const SharedKnowledgeList: React.FC<SharedKnowledgeListProps> = ({
  entries,
  loading,
  className,
}) => {
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

  return (
    <Card className={className}>
      <CardHeader title={`Shared Knowledge (${entries.length})`} />
      <CardContent>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-theme">
                <th className="text-left py-2 px-3 text-theme-secondary font-medium">Title</th>
                <th className="text-left py-2 px-3 text-theme-secondary font-medium">Type</th>
                <th className="text-left py-2 px-3 text-theme-secondary font-medium">Access</th>
                <th className="text-left py-2 px-3 text-theme-secondary font-medium">Tags</th>
                <th className="text-right py-2 px-3 text-theme-secondary font-medium">Quality</th>
                <th className="text-right py-2 px-3 text-theme-secondary font-medium">Usage</th>
                <th className="text-center py-2 px-3 text-theme-secondary font-medium">Embedding</th>
              </tr>
            </thead>
            <tbody>
              {entries.map((entry) => (
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
