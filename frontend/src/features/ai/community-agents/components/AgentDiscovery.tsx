import React, { useState, useEffect, useCallback } from 'react';
import {
  Search,
  RefreshCw,
  Globe,
  CheckCircle,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { communityAgentsApi } from '@/shared/services/ai';
import { skillsApi } from '@/features/ai/skills/services/skillsApi';
import { AgentCard } from './AgentCard';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { cn } from '@/shared/utils/cn';
import type { CommunityAgentSummary, CommunityAgentFilters } from '@/shared/services/ai';
import type { SkillCategory } from '@/features/ai/skills/types';

interface AgentDiscoveryProps {
  onSelectAgent?: (agent: CommunityAgentSummary) => void;
  onInvokeAgent?: (agent: CommunityAgentSummary) => void;
  className?: string;
}

const sortOptions = [
  { value: 'reputation', label: 'Reputation' },
  { value: 'popular', label: 'Most Used' },
  { value: 'rating', label: 'Highest Rated' },
  { value: 'recent', label: 'Recently Added' },
];

export const AgentDiscovery: React.FC<AgentDiscoveryProps> = ({
  onSelectAgent,
  onInvokeAgent,
  className,
}) => {
  const [agents, setAgents] = useState<CommunityAgentSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<string>('');
  const [verifiedOnly, setVerifiedOnly] = useState(false);
  const [sortBy, setSortBy] = useState<string>('reputation');
  const [skillFilter, setSkillFilter] = useState<string>('');
  const [skillCategories, setSkillCategories] = useState<SkillCategory[]>([]);
  const [categories, setCategories] = useState<string[]>([]);
  const [totalCount, setTotalCount] = useState(0);

  // Load categories and skill categories
  useEffect(() => {
    const loadCategories = async () => {
      try {
        const response = await communityAgentsApi.getCategories();
        setCategories(response.categories || []);
      } catch {
        // Categories may not be available
      }
    };
    const loadSkillCategories = async () => {
      const response = await skillsApi.getCategories();
      if (response.success && response.data) {
        setSkillCategories(response.data.categories);
      }
    };
    loadCategories();
    loadSkillCategories();
  }, []);

  const loadAgents = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const filters: CommunityAgentFilters = {
        per_page: 50,
        sort: sortBy as CommunityAgentFilters['sort'],
      };
      if (searchQuery) filters.query = searchQuery;
      if (categoryFilter) filters.category = categoryFilter;
      if (skillFilter) filters.skill = skillFilter;
      if (verifiedOnly) filters.verified = true;

      const response = await communityAgentsApi.getAgents(filters);
      setAgents(response.items || []);
      setTotalCount(response.pagination?.total_count || 0);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load agents');
    } finally {
      setLoading(false);
    }
  }, [searchQuery, categoryFilter, skillFilter, verifiedOnly, sortBy]);

  useEffect(() => {
    loadAgents();
  }, [loadAgents]);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    loadAgents();
  };

  if (loading && agents.length === 0) {
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
          <h2 className="text-lg font-semibold text-theme-text-primary">Community Agents</h2>
          <p className="text-sm text-theme-text-secondary">
            {totalCount} agent{totalCount !== 1 ? 's' : ''} available
          </p>
        </div>
      </div>

      {/* Search and Filters */}
      <form onSubmit={handleSearch} className="flex items-center gap-4">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-text-secondary" />
          <Input
            placeholder="Search agents by name, skill, or description..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-10"
          />
        </div>
        <Select
          value={categoryFilter}
          onChange={(value) => setCategoryFilter(value)}
          className="w-40"
        >
          <option value="">All Categories</option>
          {categories.map((category) => (
            <option key={category} value={category}>
              {category}
            </option>
          ))}
        </Select>
        <Select
          value={skillFilter}
          onChange={(value) => setSkillFilter(value)}
          className="w-36"
        >
          <option value="">All Skills</option>
          {skillCategories.map((category) => (
            <option key={category} value={category}>
              {skillsApi.getCategoryLabel(category)}
            </option>
          ))}
        </Select>
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
          variant={verifiedOnly ? 'primary' : 'outline'}
          onClick={() => setVerifiedOnly(!verifiedOnly)}
          className="flex items-center gap-2"
        >
          <CheckCircle className="w-4 h-4" />
          Verified
        </Button>
        <Button variant="ghost" onClick={loadAgents} disabled={loading}>
          <RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} />
        </Button>
      </form>

      {/* Error */}
      {error && <ErrorAlert message={error} />}

      {/* Agent Grid */}
      {agents.length === 0 ? (
        <EmptyState
          icon={Globe}
          title="No agents found"
          description={
            searchQuery || categoryFilter || skillFilter
              ? 'Try adjusting your search or filters'
              : 'No community agents are available yet'
          }
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {agents.map((agent) => (
            <AgentCard
              key={agent.id}
              agent={agent}
              onSelect={onSelectAgent}
              onInvoke={onInvokeAgent}
            />
          ))}
        </div>
      )}
    </div>
  );
};

export default AgentDiscovery;
