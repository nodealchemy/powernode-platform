import React, { useState, useEffect, useCallback } from 'react';
import {
  Search,
  RefreshCw,
  FileCode,
  Globe,
  Lock,
  Building2,
  Play,
  CheckCircle,
  AlertTriangle,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { containerExecutionApi } from '@/shared/services/ai';
import { cn } from '@/shared/utils/cn';
import type { ContainerTemplateSummary, ContainerTemplateFilters, TemplateVisibility, TemplateStatus } from '@/shared/services/ai';

interface TemplateListProps {
  onSelectTemplate?: (template: ContainerTemplateSummary) => void;
  onExecuteTemplate?: (template: ContainerTemplateSummary) => void;
  className?: string;
}

const visibilityIcons: Record<TemplateVisibility, React.FC<{ className?: string }>> = {
  private: Lock,
  account: Building2,
  public: Globe,
};

const statusConfig: Record<TemplateStatus, { variant: 'success' | 'warning' | 'outline'; label: string }> = {
  draft: { variant: 'outline', label: 'Draft' },
  active: { variant: 'success', label: 'Active' },
  deprecated: { variant: 'warning', label: 'Deprecated' },
};

const sortOptions = [
  { value: 'popular', label: 'Most Popular' },
  { value: 'recent', label: 'Recently Added' },
  { value: 'name', label: 'Name' },
];

export const TemplateList: React.FC<TemplateListProps> = ({
  onSelectTemplate,
  onExecuteTemplate,
  className,
}) => {
  const [templates, setTemplates] = useState<ContainerTemplateSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<string>('popular');
  const [showPublic, setShowPublic] = useState(false);
  const [totalCount, setTotalCount] = useState(0);

  const loadTemplates = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const filters: ContainerTemplateFilters = {
        per_page: 50,
        sort: sortBy as ContainerTemplateFilters['sort'],
        active: true,
      };
      if (searchQuery) filters.query = searchQuery;
      if (showPublic) filters.public = true;

      const response = await containerExecutionApi.getTemplates(filters);
      setTemplates(response.items || []);
      setTotalCount(response.pagination?.total_count || 0);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load templates');
    } finally {
      setLoading(false);
    }
  }, [searchQuery, sortBy, showPublic]);

  useEffect(() => {
    loadTemplates();
  }, [loadTemplates]);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    loadTemplates();
  };

  if (loading && templates.length === 0) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loading size="lg" />
      </div>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-theme-text-primary">Container Templates</h2>
          <p className="text-sm text-theme-text-secondary">
            {totalCount} template{totalCount !== 1 ? 's' : ''} available
          </p>
        </div>
      </div>

      {/* Search and Filters */}
      <form onSubmit={handleSearch} className="flex items-center gap-4">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-text-secondary" />
          <Input
            placeholder="Search templates..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-10"
          />
        </div>
        <Select
          value={sortBy}
          onChange={(value) => setSortBy(value)}
          className="w-40"
        >
          {sortOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
        <Button
          type="button"
          variant={showPublic ? 'primary' : 'outline'}
          onClick={() => setShowPublic(!showPublic)}
          className="flex items-center gap-2"
        >
          <Globe className="w-4 h-4" />
          Public
        </Button>
        <Button variant="ghost" onClick={loadTemplates} disabled={loading}>
          <RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} />
        </Button>
      </form>

      {/* Error */}
      {error && (
        <div className="p-4 rounded-lg bg-theme-status-error/10 text-theme-status-error">
          {error}
        </div>
      )}

      {/* Template Grid */}
      {templates.length === 0 ? (
        <EmptyState
          icon={FileCode}
          title="No templates found"
          description={
            searchQuery
              ? 'Try adjusting your search'
              : 'No container templates are available yet'
          }
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {templates.map((template) => {
            const VisibilityIcon = visibilityIcons[template.visibility];
            const status = statusConfig[template.status] || statusConfig.draft;

            return (
              <Card
                key={template.id}
                className={cn(
                  'cursor-pointer transition-all hover:shadow-md',
                  'border-theme-border-primary'
                )}
                onClick={() => onSelectTemplate?.(template)}
              >
                <CardContent className="p-4">
                  {/* Header */}
                  <div className="flex items-start justify-between mb-3">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <FileCode className="w-5 h-5 text-theme-text-secondary flex-shrink-0" />
                        <h3 className="font-medium text-theme-text-primary truncate">
                          {template.name}
                        </h3>
                      </div>
                      <div className="flex items-center gap-2 mt-1 text-xs text-theme-text-secondary">
                        <VisibilityIcon className="w-3 h-3" />
                        <span className="capitalize">{template.visibility}</span>
                        {template.category && (
                          <>
                            <span>•</span>
                            <span>{template.category}</span>
                          </>
                        )}
                      </div>
                    </div>
                    <Badge variant={status.variant} size="sm">
                      {status.label}
                    </Badge>
                  </div>

                  {/* Description */}
                  {template.description && (
                    <p className="text-sm text-theme-text-secondary line-clamp-2 mb-3">
                      {template.description}
                    </p>
                  )}

                  {/* Image */}
                  <div className="text-xs text-theme-text-secondary font-mono bg-theme-bg-secondary px-2 py-1 rounded mb-3 truncate">
                    {template.image_name}
                  </div>

                  {/* Stats */}
                  <div className="flex items-center gap-4 text-sm text-theme-text-secondary mb-3">
                    <div className="flex items-center gap-1">
                      <Play className="w-4 h-4" />
                      <span>{template.execution_count} runs</span>
                    </div>
                    {template.success_rate !== undefined && (
                      <div className="flex items-center gap-1">
                        {template.success_rate >= 90 ? (
                          <CheckCircle className="w-4 h-4 text-theme-status-success" />
                        ) : template.success_rate >= 70 ? (
                          <AlertTriangle className="w-4 h-4 text-theme-status-warning" />
                        ) : (
                          <AlertTriangle className="w-4 h-4 text-theme-status-error" />
                        )}
                        <span>{template.success_rate.toFixed(0)}% success</span>
                      </div>
                    )}
                  </div>

                  {/* Footer */}
                  <div className="flex items-center justify-end pt-3 border-t border-theme-border-primary">
                    <Button
                      variant="primary"
                      size="sm"
                      onClick={(e) => {
                        e.stopPropagation();
                        onExecuteTemplate?.(template);
                      }}
                    >
                      <Play className="w-3 h-3 mr-1" />
                      Execute
                    </Button>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default TemplateList;
