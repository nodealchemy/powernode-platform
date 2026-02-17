import React, { useEffect, useState } from 'react';
import { Loader2 } from 'lucide-react';
import { repositoriesApi } from '@/features/devops/git/services/git/repositoriesApi';
import type { MissionType } from '../../types/mission';

interface RepoOption {
  id: string;
  full_name: string;
  default_branch: string;
}

interface BranchOption {
  name: string;
}

interface StepTypeAndRepoProps {
  name: string;
  onNameChange: (v: string) => void;
  missionType: MissionType;
  onMissionTypeChange: (v: MissionType) => void;
  repositoryId: string;
  onRepositoryIdChange: (v: string) => void;
  baseBranch: string;
  onBaseBranchChange: (v: string) => void;
}

const MISSION_TYPES: { value: MissionType; label: string; description: string; icon: string }[] = [
  { value: 'development', label: 'Development', description: 'Build features, fix bugs, refactor code', icon: '\u{1F6E0}' },
  { value: 'research', label: 'Research', description: 'Analyze codebases, generate reports', icon: '\u{1F52C}' },
  { value: 'operations', label: 'Operations', description: 'DevOps tasks, deployments, configuration', icon: '\u{2699}' },
];

export const StepTypeAndRepo: React.FC<StepTypeAndRepoProps> = ({
  name,
  onNameChange,
  missionType,
  onMissionTypeChange,
  repositoryId,
  onRepositoryIdChange,
  baseBranch,
  onBaseBranchChange,
}) => {
  const [repos, setRepos] = useState<RepoOption[]>([]);
  const [loadingRepos, setLoadingRepos] = useState(true);
  const [branches, setBranches] = useState<BranchOption[]>([]);
  const [loadingBranches, setLoadingBranches] = useState(false);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      try {
        const data = await repositoriesApi.getRepositories({ per_page: 100 });
        if (!cancelled) {
          setRepos(data.repositories.map(r => ({
            id: r.id,
            full_name: r.full_name,
            default_branch: r.default_branch,
          })));
        }
      } catch {
        // Repos are optional — silently fall back to empty list
      } finally {
        if (!cancelled) setLoadingRepos(false);
      }
    };
    load();
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    if (!repositoryId) {
      setBranches([]);
      return;
    }
    let cancelled = false;
    const loadBranches = async () => {
      setLoadingBranches(true);
      try {
        const data = await repositoriesApi.getBranchesTyped(repositoryId, { per_page: 100 });
        if (!cancelled) {
          setBranches(data.map(b => ({ name: b.name })));
        }
      } catch {
        if (!cancelled) setBranches([]);
      } finally {
        if (!cancelled) setLoadingBranches(false);
      }
    };
    loadBranches();
    return () => { cancelled = true; };
  }, [repositoryId]);

  const handleRepoChange = (repoId: string) => {
    onRepositoryIdChange(repoId);
    setBranches([]);
    if (repoId) {
      const selected = repos.find(r => r.id === repoId);
      if (selected) {
        onBaseBranchChange(selected.default_branch);
      }
    } else {
      onBaseBranchChange('main');
    }
  };

  return (
    <div className="space-y-5">
      {/* Mission name */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1.5">
          Mission Name <span className="text-theme-error">*</span>
        </label>
        <input
          type="text"
          value={name}
          onChange={(e) => onNameChange(e.target.value)}
          placeholder="e.g., Add user authentication"
          className="input-theme w-full"
          autoFocus
        />
      </div>

      {/* Mission type */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1.5">Mission Type</label>
        <div className="grid grid-cols-3 gap-2">
          {MISSION_TYPES.map((t) => (
            <button
              key={t.value}
              onClick={() => onMissionTypeChange(t.value)}
              className={`p-3 rounded-lg border text-left transition-all ${
                missionType === t.value
                  ? 'border-theme-accent bg-theme-accent/5 ring-1 ring-theme-accent/30'
                  : 'border-theme-border bg-theme-surface hover:border-theme-accent/50'
              }`}
            >
              <span className="text-lg">{t.icon}</span>
              <p className="text-xs font-medium text-theme-primary mt-1">{t.label}</p>
              <p className="text-[10px] text-theme-tertiary mt-0.5">{t.description}</p>
            </button>
          ))}
        </div>
      </div>

      {/* Repository selector */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1.5">
          Repository <span className="text-xs text-theme-tertiary">
            {missionType === 'development' ? '(required)' : '(optional)'}
          </span>
        </label>
        {loadingRepos ? (
          <div className="flex items-center gap-2 text-sm text-theme-tertiary py-2">
            <Loader2 className="w-4 h-4 animate-spin" />
            Loading repositories...
          </div>
        ) : (
          <select
            value={repositoryId}
            onChange={(e) => handleRepoChange(e.target.value)}
            className="input-theme w-full"
          >
            <option value="">Select a repository</option>
            {repos.map((repo) => (
              <option key={repo.id} value={repo.id}>
                {repo.full_name}
              </option>
            ))}
          </select>
        )}
        {repos.length === 0 && !loadingRepos && (
          <p className="text-xs text-theme-tertiary mt-1">
            No repositories found. Add one in Source Control settings.
          </p>
        )}
      </div>

      {/* Base branch */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1.5">Base Branch</label>
        {loadingBranches ? (
          <div className="flex items-center gap-2 text-sm text-theme-tertiary py-2">
            <Loader2 className="w-4 h-4 animate-spin" />
            Loading branches...
          </div>
        ) : branches.length > 0 ? (
          <select
            value={baseBranch}
            onChange={(e) => onBaseBranchChange(e.target.value)}
            className="input-theme w-full"
          >
            {branches.map((branch) => (
              <option key={branch.name} value={branch.name}>
                {branch.name}
              </option>
            ))}
          </select>
        ) : (
          <input
            type="text"
            value={baseBranch}
            onChange={(e) => onBaseBranchChange(e.target.value)}
            placeholder="main"
            className="input-theme w-full"
          />
        )}
      </div>
    </div>
  );
};
