import React from 'react';
import {
  FileText, GitBranch, GitMerge, Terminal,
  Database, Map, CheckSquare, Play
} from 'lucide-react';
import type { ResourceCounts, ResourceType } from '../types';

interface ResourceStatsBarProps {
  counts: ResourceCounts;
  activeType?: ResourceType;
  onTypeClick: (type: ResourceType | undefined) => void;
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

export function ResourceStatsBar({ counts, activeType, onTypeClick }: ResourceStatsBarProps) {
  return (
    <div className="flex flex-wrap gap-2 mb-4">
      <button
        onClick={() => onTypeClick(undefined)}
        className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${
          !activeType
            ? 'bg-theme-interactive-primary text-white'
            : 'bg-theme-surface text-theme-secondary hover:bg-theme-surface-hover'
        }`}
      >
        All ({counts.total || 0})
      </button>
      {(Object.entries(TYPE_CONFIG) as [ResourceType, { icon: React.ElementType; label: string }][]).map(
        ([type, config]) => {
          const count = counts[type] || 0;
          if (count === 0) return null;
          const Icon = config.icon;
          return (
            <button
              key={type}
              onClick={() => onTypeClick(activeType === type ? undefined : type)}
              className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${
                activeType === type
                  ? 'bg-theme-interactive-primary text-white'
                  : 'bg-theme-surface text-theme-secondary hover:bg-theme-surface-hover'
              }`}
            >
              <Icon className="w-3.5 h-3.5" />
              {config.label} ({count})
            </button>
          );
        }
      )}
    </div>
  );
}
