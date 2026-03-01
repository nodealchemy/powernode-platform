// Trajectory List - Browsable trajectory list with search and filter
import React, { useEffect, useState, useCallback } from 'react';
import { Search, Star, BookOpen, Eye, Clock, Tag, Filter } from 'lucide-react';
import teamsApi from '@/shared/services/ai/TeamsApiService';
import type { Trajectory } from '@/shared/services/ai/TeamsApiService';

interface TrajectoryListProps {
  onSelectTrajectory: (trajectoryId: string) => void;
}

const TRAJECTORY_TYPE_LABELS: Record<string, string> = {
  task_completion: 'Task Completion',
  workflow_run: 'Workflow Run',
  investigation: 'Investigation',
  implementation: 'Implementation',
};

const formatTimeAgo = (dateStr: string): string => {
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffDays > 0) return `${diffDays}d ago`;
  if (diffHours > 0) return `${diffHours}h ago`;
  if (diffMins > 0) return `${diffMins}m ago`;
  return 'just now';
};

export const TrajectoryList: React.FC<TrajectoryListProps> = ({
  onSelectTrajectory
}) => {
  const [trajectories, setTrajectories] = useState<Trajectory[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<string>('');

  const fetchTrajectories = useCallback(async () => {
    setLoading(true);
    try {
      const filters: Record<string, string | string[]> = {};
      if (typeFilter) filters.type = typeFilter;
      if (searchQuery) filters.query = searchQuery;

      const data = await teamsApi.listTrajectories(filters);
      setTrajectories(data);
    } catch {
      // Error handled by API service
    } finally {
      setLoading(false);
    }
  }, [searchQuery, typeFilter]);

  useEffect(() => {
    const debounce = setTimeout(fetchTrajectories, 300);
    return () => clearTimeout(debounce);
  }, [fetchTrajectories]);

  return (
    <div className="space-y-4" data-testid="trajectory-list">
      {/* Header & Search */}
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-theme-primary">Trajectories</h2>
      </div>

      {/* Search & Filter Bar */}
      <div className="flex gap-3">
        <div className="relative flex-1">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-theme-secondary" />
          <input
            type="text"
            placeholder="Search trajectories..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          />
        </div>

        <div className="relative">
          <Filter size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-theme-secondary pointer-events-none" />
          <select
            value={typeFilter}
            onChange={(e) => setTypeFilter(e.target.value)}
            className="pl-9 pr-8 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary appearance-none"
          >
            <option value="">All Types</option>
            {Object.entries(TRAJECTORY_TYPE_LABELS).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
        </div>
      </div>

      {/* Trajectory Cards */}
      {loading ? (
        <div className="flex items-center justify-center py-12 text-theme-secondary text-sm">
          Loading trajectories...
        </div>
      ) : trajectories.length === 0 ? (
        <div className="text-center py-12 text-theme-secondary">
          <BookOpen size={32} className="mx-auto mb-3 opacity-50" />
          <p className="text-sm">No trajectories found</p>
          {searchQuery && (
            <p className="text-xs mt-1">Try adjusting your search query</p>
          )}
        </div>
      ) : (
        <div className="space-y-3">
          {trajectories.map(trajectory => (
            <button
              key={trajectory.id}
              type="button"
              onClick={() => onSelectTrajectory(trajectory.id)}
              className="w-full text-left bg-theme-surface border border-theme rounded-lg p-4 hover:shadow-md hover:border-theme-info/30 transition-all"
              data-testid={`trajectory-card-${trajectory.trajectory_id}`}
            >
              <div className="flex items-start justify-between mb-2">
                <h3 className="text-sm font-medium text-theme-primary line-clamp-1">
                  {trajectory.title}
                </h3>

                <div className="flex items-center gap-2 shrink-0 ml-3">
                  {trajectory.quality_score !== null && trajectory.quality_score !== undefined && (
                    <span className="flex items-center gap-1 text-xs text-theme-warning">
                      <Star size={12} />
                      {trajectory.quality_score.toFixed(2)}
                    </span>
                  )}
                  <span className="text-xs text-theme-secondary">
                    {trajectory.chapter_count} ch
                  </span>
                </div>
              </div>

              <div className="flex items-center gap-3 text-xs text-theme-secondary">
                <span className="px-1.5 py-0.5 rounded bg-theme-accent">
                  {TRAJECTORY_TYPE_LABELS[trajectory.trajectory_type] || trajectory.trajectory_type}
                </span>
                <span className="flex items-center gap-1">
                  <Clock size={10} />
                  {formatTimeAgo(trajectory.created_at)}
                </span>
                <span className="flex items-center gap-1">
                  <Eye size={10} />
                  viewed {trajectory.access_count}x
                </span>
              </div>

              {/* Tags */}
              {trajectory.tags && trajectory.tags.length > 0 && (
                <div className="flex flex-wrap gap-1 mt-2">
                  {trajectory.tags.map((tag: string, idx: number) => (
                    <span key={idx} className="flex items-center gap-0.5 px-1.5 py-0.5 text-xs rounded bg-theme-accent text-theme-secondary">
                      <Tag size={8} />
                      {tag}
                    </span>
                  ))}
                </div>
              )}

              {/* Summary */}
              {trajectory.summary && (
                <p className="mt-2 text-xs text-theme-secondary line-clamp-2">
                  {trajectory.summary}
                </p>
              )}
            </button>
          ))}
        </div>
      )}
    </div>
  );
};
