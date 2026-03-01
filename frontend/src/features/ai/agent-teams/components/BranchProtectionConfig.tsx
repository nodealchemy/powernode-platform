import React, { useState } from 'react';
import { Shield, X, Plus } from 'lucide-react';

export interface BranchProtectionSettings {
  branch_protection_enabled: boolean;
  protected_branches: string[];
  require_worktree_for_repos: boolean;
  merge_approval_required: boolean;
}

interface BranchProtectionConfigProps {
  config: BranchProtectionSettings;
  onUpdate: (config: BranchProtectionSettings) => void;
}

export const BranchProtectionConfig: React.FC<BranchProtectionConfigProps> = ({ config, onUpdate }) => {
  const [newBranch, setNewBranch] = useState('');

  const handleToggle = (field: keyof BranchProtectionSettings) => {
    onUpdate({ ...config, [field]: !config[field] });
  };

  const addBranch = () => {
    const trimmed = newBranch.trim();
    if (trimmed && !config.protected_branches.includes(trimmed)) {
      onUpdate({
        ...config,
        protected_branches: [...config.protected_branches, trimmed],
      });
      setNewBranch('');
    }
  };

  const removeBranch = (branch: string) => {
    onUpdate({
      ...config,
      protected_branches: config.protected_branches.filter((b) => b !== branch),
    });
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      addBranch();
    }
  };

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4 space-y-4">
      <div className="flex items-center gap-2 mb-2">
        <Shield className="h-4 w-4 text-theme-primary" />
        <h4 className="text-sm font-semibold text-theme-primary">Branch Protection</h4>
      </div>

      {/* Master Toggle */}
      <label className="flex items-center justify-between cursor-pointer">
        <span className="text-sm text-theme-primary">Enable Branch Protection</span>
        <button
          type="button"
          role="switch"
          aria-checked={config.branch_protection_enabled}
          onClick={() => handleToggle('branch_protection_enabled')}
          className={`relative w-10 h-5 rounded-full transition-colors ${
            config.branch_protection_enabled ? 'bg-theme-primary' : 'bg-theme-accent'
          }`}
        >
          <span
            className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white transition-transform ${
              config.branch_protection_enabled ? 'translate-x-5' : ''
            }`}
          />
        </button>
      </label>

      {config.branch_protection_enabled && (
        <>
          {/* Protected Branches */}
          <div>
            <span className="text-sm text-theme-primary block mb-2">Protected Branches</span>
            <div className="flex flex-wrap gap-2 mb-2">
              {config.protected_branches.map((branch) => (
                <span
                  key={branch}
                  className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-md bg-theme-primary/10 text-theme-primary border border-theme-primary/20"
                >
                  {branch}
                  <button
                    type="button"
                    onClick={() => removeBranch(branch)}
                    className="hover:text-theme-error transition-colors"
                  >
                    <X className="h-3 w-3" />
                  </button>
                </span>
              ))}
            </div>
            <div className="flex gap-2">
              <input
                type="text"
                value={newBranch}
                onChange={(e) => setNewBranch(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Add branch pattern (e.g. release/*)"
                className="flex-1 px-3 py-1.5 text-sm bg-theme-bg border border-theme rounded-md text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-1 focus:ring-theme-primary"
              />
              <button
                type="button"
                onClick={addBranch}
                disabled={!newBranch.trim()}
                className="px-3 py-1.5 text-sm font-medium rounded-md bg-theme-primary text-white hover:bg-theme-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                <Plus className="h-4 w-4" />
              </button>
            </div>
          </div>

          {/* Require Worktree Toggle */}
          <label className="flex items-center justify-between cursor-pointer">
            <span className="text-sm text-theme-primary">Require Worktree for Repos</span>
            <button
              type="button"
              role="switch"
              aria-checked={config.require_worktree_for_repos}
              onClick={() => handleToggle('require_worktree_for_repos')}
              className={`relative w-10 h-5 rounded-full transition-colors ${
                config.require_worktree_for_repos ? 'bg-theme-primary' : 'bg-theme-accent'
              }`}
            >
              <span
                className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white transition-transform ${
                  config.require_worktree_for_repos ? 'translate-x-5' : ''
                }`}
              />
            </button>
          </label>

          {/* Merge Approval Toggle */}
          <label className="flex items-center justify-between cursor-pointer">
            <span className="text-sm text-theme-primary">Require Merge Approval</span>
            <button
              type="button"
              role="switch"
              aria-checked={config.merge_approval_required}
              onClick={() => handleToggle('merge_approval_required')}
              className={`relative w-10 h-5 rounded-full transition-colors ${
                config.merge_approval_required ? 'bg-theme-primary' : 'bg-theme-accent'
              }`}
            >
              <span
                className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white transition-transform ${
                  config.merge_approval_required ? 'translate-x-5' : ''
                }`}
              />
            </button>
          </label>
        </>
      )}
    </div>
  );
};
