import React, { useCallback, useState } from 'react';
import {
  FileText, GitBranch, GitMerge, Terminal,
  Database, Map, CheckSquare, Play,
  Search, ChevronLeft, ChevronRight, FolderOutput, Loader2
} from 'lucide-react';
import { ResizableListPanel } from '@/shared/components/layout/ResizableListPanel';
import { ResourceListItem } from './ResourceListItem';
import type { ExecutionResource, ResourceCounts, ResourceFilters, ResourceType } from '../types';

interface ResourceListPanelProps {
  resources: ExecutionResource[];
  counts: ResourceCounts;
  loading: boolean;
  selectedResourceId: string | null;
  onSelectResource: (resource: ExecutionResource) => void;
  pagination: { current_page: number; total_pages: number; total_count: number; per_page: number };
  onPageChange: (page: number) => void;
  filters: ResourceFilters;
  onFilterChange: (filters: Partial<ResourceFilters>) => void;
  refreshKey?: number;
}

const TYPE_CONFIG: Record<ResourceType, { icon: React.ElementType; label: string }> = {
  artifact: { icon: FileText, label: 'Artifacts' },
  git_branch: { icon: GitBranch, label: 'Branches' },
  git_merge: { icon: GitMerge, label: 'Merges' },
  execution_output: { icon: Terminal, label: 'Outputs' },
  shared_memory: { icon: Database, label: 'Memory' },
  trajectory: { icon: Map, label: 'Trajectories' },
  review: { icon: CheckSquare, label: 'Reviews' },
  runner_job: { icon: Play, label: 'Runner Jobs' },
};

const ALL_TYPES: ResourceType[] = [
  'artifact', 'git_branch', 'git_merge', 'execution_output',
  'shared_memory', 'trajectory', 'review', 'runner_job'
];

export function ResourceListPanel({
  resources,
  counts,
  loading,
  selectedResourceId,
  onSelectResource,
  pagination,
  onPageChange,
  filters,
  onFilterChange,
}: ResourceListPanelProps) {
  const [focusIndex, setFocusIndex] = useState(-1);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setFocusIndex(prev => Math.min(prev + 1, resources.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setFocusIndex(prev => Math.max(prev - 1, 0));
    } else if (e.key === 'Enter' && focusIndex >= 0 && focusIndex < resources.length) {
      e.preventDefault();
      onSelectResource(resources[focusIndex]);
    }
  }, [focusIndex, resources, onSelectResource]);

  const tabPills = (
    <div className="flex flex-wrap gap-1 px-3 py-2 border-b border-theme">
      <button
        onClick={() => onFilterChange({ type: undefined })}
        className={`inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium transition-colors ${
          !filters.type
            ? 'bg-theme-interactive-primary text-white'
            : 'bg-theme-surface text-theme-secondary hover:bg-theme-surface-hover'
        }`}
      >
        All ({counts.total || 0})
      </button>
      {ALL_TYPES.map(type => {
        const count = counts[type] || 0;
        if (count === 0) return null;
        const config = TYPE_CONFIG[type];
        const Icon = config.icon;
        return (
          <button
            key={type}
            onClick={() => onFilterChange({ type: filters.type === type ? undefined : type })}
            className={`inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium transition-colors ${
              filters.type === type
                ? 'bg-theme-interactive-primary text-white'
                : 'bg-theme-surface text-theme-secondary hover:bg-theme-surface-hover'
            }`}
          >
            <Icon className="w-3 h-3" />
            {count}
          </button>
        );
      })}
    </div>
  );

  const searchInput = (
    <div className="px-3 py-2 border-b border-theme">
      <div className="relative">
        <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-theme-tertiary" />
        <input
          type="text"
          value={filters.search || ''}
          onChange={(e) => onFilterChange({ search: e.target.value || undefined })}
          placeholder="Search resources..."
          className="w-full pl-8 pr-3 py-1.5 text-sm rounded-lg border border-theme bg-theme-bg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
        />
      </div>
    </div>
  );

  const footer = pagination.total_pages > 1 ? (
    <div className="flex items-center justify-between px-3 py-2 border-t border-theme">
      <button
        onClick={() => onPageChange(pagination.current_page - 1)}
        disabled={pagination.current_page <= 1}
        className="p-1 rounded text-theme-secondary hover:text-theme-primary disabled:opacity-40 disabled:cursor-not-allowed"
      >
        <ChevronLeft className="w-4 h-4" />
      </button>
      <span className="text-xs text-theme-tertiary">
        Page {pagination.current_page} of {pagination.total_pages}
      </span>
      <button
        onClick={() => onPageChange(pagination.current_page + 1)}
        disabled={pagination.current_page >= pagination.total_pages}
        className="p-1 rounded text-theme-secondary hover:text-theme-primary disabled:opacity-40 disabled:cursor-not-allowed"
      >
        <ChevronRight className="w-4 h-4" />
      </button>
    </div>
  ) : undefined;

  const collapsedContent = (
    <>
      {ALL_TYPES.map(type => {
        const count = counts[type] || 0;
        if (count === 0) return null;
        const config = TYPE_CONFIG[type];
        const Icon = config.icon;
        return (
          <button
            key={type}
            onClick={() => onFilterChange({ type: filters.type === type ? undefined : type })}
            className={`p-1.5 rounded transition-colors ${
              filters.type === type
                ? 'bg-theme-interactive-primary text-white'
                : 'text-theme-tertiary hover:text-theme-primary hover:bg-theme-surface-hover'
            }`}
            title={`${config.label} (${count})`}
          >
            <Icon className="w-4 h-4" />
          </button>
        );
      })}
    </>
  );

  return (
    <ResizableListPanel
      storageKeyPrefix="resources-panel"
      title="Resources"
      tabPills={tabPills}
      search={searchInput}
      footer={footer}
      collapsedContent={collapsedContent}
      onKeyDown={handleKeyDown}
    >
      {loading && resources.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-12 text-theme-tertiary">
          <Loader2 className="w-5 h-5 animate-spin mb-2" />
          <span className="text-xs">Loading resources...</span>
        </div>
      ) : resources.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-12 text-theme-tertiary">
          <FolderOutput className="w-8 h-8 mb-2 opacity-40" />
          <span className="text-xs">No resources found</span>
        </div>
      ) : (
        resources.map((resource, idx) => (
          <ResourceListItem
            key={`${resource.resource_type}-${resource.id}`}
            resource={resource}
            isSelected={resource.id === selectedResourceId || idx === focusIndex}
            onClick={() => {
              setFocusIndex(idx);
              onSelectResource(resource);
            }}
          />
        ))
      )}
    </ResizableListPanel>
  );
}
