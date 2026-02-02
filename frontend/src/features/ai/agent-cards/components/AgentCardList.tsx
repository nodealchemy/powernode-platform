import React, { useState, useEffect, useCallback } from 'react';
import {
  Bot,
  Globe,
  Lock,
  Building2,
  Search,
  Filter,
  ExternalLink,
  Clock,
  CheckCircle,
  AlertCircle,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { agentCardsApiService } from '@/shared/services/ai';
import { CapabilityList } from './CapabilityBadge';
import { cn } from '@/shared/utils/cn';
import type { AgentCard, AgentCardFilters } from '@/shared/services/ai/types/a2a-types';

interface AgentCardListProps {
  onSelectCard?: (card: AgentCard) => void;
  onEditCard?: (card: AgentCard) => void;
  className?: string;
}

const visibilityIcons: Record<string, React.FC<{ className?: string }>> = {
  public: Globe,
  internal: Building2,
  private: Lock,
};

const statusConfig: Record<string, { variant: 'success' | 'warning' | 'danger' | 'outline'; label: string }> = {
  active: { variant: 'success', label: 'Active' },
  inactive: { variant: 'outline', label: 'Inactive' },
  deprecated: { variant: 'warning', label: 'Deprecated' },
};

export const AgentCardList: React.FC<AgentCardListProps> = ({
  onSelectCard,
  onEditCard,
  className,
}) => {
  const [cards, setCards] = useState<AgentCard[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [visibilityFilter, setVisibilityFilter] = useState<string>('');
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [totalCount, setTotalCount] = useState(0);

  const loadCards = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const filters: AgentCardFilters = {};
      if (searchQuery) filters.search = searchQuery;
      if (visibilityFilter) filters.visibility = visibilityFilter as AgentCardFilters['visibility'];
      if (statusFilter) filters.status = statusFilter as AgentCardFilters['status'];

      const response = await agentCardsApiService.getAgentCards(filters);
      setCards(response.items || []);
      setTotalCount(response.pagination?.total_count || 0);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to load agent cards');
    } finally {
      setLoading(false);
    }
  }, [searchQuery, visibilityFilter, statusFilter]);

  useEffect(() => {
    loadCards();
  }, [loadCards]);

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  };

  if (loading && cards.length === 0) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-12">
          <Loading size="lg" message="Loading agent cards..." />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      {/* Filters */}
      <div className="flex flex-wrap items-center gap-4">
        <div className="flex-1 min-w-64">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-muted" />
            <Input
              placeholder="Search agent cards..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10"
            />
          </div>
        </div>

        <div className="flex items-center gap-2">
          <Filter className="h-4 w-4 text-theme-muted" />
          <Select
            value={visibilityFilter}
            onChange={(value) => setVisibilityFilter(value)}
            className="w-32"
          >
            <option value="">All Visibility</option>
            <option value="public">Public</option>
            <option value="internal">Internal</option>
            <option value="private">Private</option>
          </Select>

          <Select
            value={statusFilter}
            onChange={(value) => setStatusFilter(value)}
            className="w-32"
          >
            <option value="">All Status</option>
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
            <option value="deprecated">Deprecated</option>
          </Select>
        </div>

      </div>

      {/* Stats bar */}
      <div className="flex items-center justify-between text-sm text-theme-muted">
        <span>{totalCount} agent card{totalCount !== 1 ? 's' : ''}</span>
      </div>

      {/* Error state */}
      {error && (
        <div className="p-4 bg-theme-danger/10 border border-theme-danger/30 rounded-lg">
          <div className="flex items-center gap-2 text-theme-danger">
            <AlertCircle className="h-4 w-4" />
            <span>{error}</span>
          </div>
        </div>
      )}

      {/* Empty state */}
      {!loading && cards.length === 0 && !error && (
        <EmptyState
          icon={Bot}
          title="No agent cards found"
          description="Create your first A2A Agent Card to enable agent discovery and communication"
        />
      )}

      {/* Cards grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4">
        {cards.map((card) => {
          const VisibilityIcon = visibilityIcons[card.visibility] || Lock;
          const status = statusConfig[card.status] || statusConfig.draft;

          return (
            <Card
              key={card.id}
              className="group hover:border-theme-primary/50 transition-colors cursor-pointer"
              onClick={() => onSelectCard?.(card)}
            >
              <CardContent className="p-4">
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-3">
                    <div className="h-10 w-10 bg-theme-info/10 rounded-lg flex items-center justify-center">
                      <Bot className="h-5 w-5 text-theme-info" />
                    </div>
                    <div>
                      <h3 className="font-semibold text-theme-primary group-hover:text-theme-info transition-colors">
                        {card.name}
                      </h3>
                      <div className="flex items-center gap-2 text-xs text-theme-muted">
                        <VisibilityIcon className="h-3 w-3" />
                        <span className="capitalize">{card.visibility}</span>
                        {card.protocol_version && (
                          <>
                            <span>•</span>
                            <span>v{card.protocol_version}</span>
                          </>
                        )}
                      </div>
                    </div>
                  </div>
                  <Badge variant={status.variant} size="sm">
                    {status.label}
                  </Badge>
                </div>

                {card.description && (
                  <p className="text-sm text-theme-secondary mb-3 line-clamp-2">
                    {card.description}
                  </p>
                )}

                {/* Capabilities */}
                {card.capabilities?.skills && card.capabilities.skills.length > 0 && (
                  <div className="mb-3">
                    <CapabilityList skills={card.capabilities.skills} maxVisible={3} />
                  </div>
                )}

                {/* Metrics */}
                <div className="flex items-center gap-4 text-xs text-theme-muted border-t border-theme pt-3 mt-3">
                  <div className="flex items-center gap-1">
                    <CheckCircle className="h-3 w-3" />
                    <span>{card.task_count || 0} tasks</span>
                  </div>
                  {card.task_count > 0 && (
                    <div className="flex items-center gap-1">
                      <span>{Math.round((card.success_count / card.task_count) * 100)}% success</span>
                    </div>
                  )}
                  <div className="flex items-center gap-1 ml-auto">
                    <Clock className="h-3 w-3" />
                    <span>{formatDate(card.updated_at)}</span>
                  </div>
                </div>

                {/* External link */}
                {card.endpoint_url && (
                  <div className="flex items-center gap-1 text-xs text-theme-info mt-2">
                    <ExternalLink className="h-3 w-3" />
                    <span className="truncate">{card.endpoint_url}</span>
                  </div>
                )}

                {/* Actions */}
                <div className="flex items-center gap-2 mt-3 pt-3 border-t border-theme opacity-0 group-hover:opacity-100 transition-opacity">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      onEditCard?.(card);
                    }}
                  >
                    Edit
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      onSelectCard?.(card);
                    }}
                  >
                    View Details
                  </Button>
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>
    </div>
  );
};

export default AgentCardList;
