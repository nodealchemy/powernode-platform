import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Button } from '@/shared/components/ui/Button';
import { GitBranch } from 'lucide-react';
import type { ParallelSessionConfig, MergeStrategy } from '../types';

interface CreateSessionModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (config: ParallelSessionConfig) => void;
  loading?: boolean;
}

export const CreateSessionModal: React.FC<CreateSessionModalProps> = ({
  isOpen,
  onClose,
  onSubmit,
  loading,
}) => {
  const [form, setForm] = useState({
    repository_path: '',
    base_branch: 'main',
    merge_strategy: 'sequential' as MergeStrategy,
    max_parallel: 4,
    branch_suffixes: '',
    container_template_id: '',
    execution_mode: 'complementary' as 'complementary' | 'competitive',
    max_duration_seconds: '',
  });

  const handleSubmit = () => {
    const suffixes = form.branch_suffixes
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);

    if (suffixes.length === 0 || !form.repository_path) return;

    onSubmit({
      repository_path: form.repository_path,
      base_branch: form.base_branch,
      merge_strategy: form.merge_strategy,
      max_parallel: form.max_parallel,
      tasks: suffixes.map((suffix) => ({
        branch_suffix: suffix,
        container_template_id: form.container_template_id || undefined,
      })),
      execution_mode: form.execution_mode,
      max_duration_seconds: form.max_duration_seconds ? parseInt(form.max_duration_seconds) : undefined,
    });
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="New Parallel Execution Session"
      icon={<GitBranch className="w-5 h-5 text-theme-brand-primary" />}
      size="md"
      footer={
        <>
          <Button variant="outline" onClick={onClose} disabled={loading}>Cancel</Button>
          <Button
            variant="primary"
            onClick={handleSubmit}
            disabled={loading || !form.repository_path || !form.branch_suffixes.trim()}
          >
            {loading ? 'Creating...' : 'Create Session'}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Repository Path *
          </label>
          <Input
            value={form.repository_path}
            onChange={(e) => setForm((prev) => ({ ...prev, repository_path: e.target.value }))}
            placeholder="/path/to/repository"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Base Branch
          </label>
          <Input
            value={form.base_branch}
            onChange={(e) => setForm((prev) => ({ ...prev, base_branch: e.target.value }))}
            placeholder="main"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Merge Strategy
          </label>
          <Select
            value={form.merge_strategy}
            onChange={(value) => setForm((prev) => ({ ...prev, merge_strategy: value as MergeStrategy }))}
          >
            <option value="sequential">Sequential</option>
            <option value="integration_branch">Integration Branch</option>
            <option value="manual">Manual (PR-based)</option>
          </Select>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Execution Mode
          </label>
          <Select
            value={form.execution_mode}
            onChange={(value) => setForm((prev) => ({ ...prev, execution_mode: value as 'complementary' | 'competitive' }))}
          >
            <option value="complementary">Complementary (merge all)</option>
            <option value="competitive">Competitive (pick best)</option>
          </Select>
          <p className="text-xs text-theme-text-secondary mt-1">
            Complementary merges all results; competitive evaluates and picks the best
          </p>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Max Parallel
          </label>
          <Input
            type="number"
            value={form.max_parallel}
            onChange={(e) => setForm((prev) => ({ ...prev, max_parallel: parseInt(e.target.value) || 4 }))}
            min={1}
            max={20}
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Container Template ID (optional)
          </label>
          <Input
            value={form.container_template_id}
            onChange={(e) => setForm((prev) => ({ ...prev, container_template_id: e.target.value }))}
            placeholder="UUID of a DevOps container template"
          />
          <p className="text-xs text-theme-text-secondary mt-1">
            Each worktree task will execute in a container using this template
          </p>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Timeout (seconds, optional)
          </label>
          <Input
            type="number"
            value={form.max_duration_seconds}
            onChange={(e) => setForm((prev) => ({ ...prev, max_duration_seconds: e.target.value }))}
            placeholder="No timeout"
            min={60}
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Branch Suffixes (comma-separated) *
          </label>
          <Input
            value={form.branch_suffixes}
            onChange={(e) => setForm((prev) => ({ ...prev, branch_suffixes: e.target.value }))}
            placeholder="feature-a, feature-b, feature-c"
          />
          <p className="text-xs text-theme-text-secondary mt-1">
            Each suffix creates a worktree branch: worktree/session/suffix
          </p>
        </div>
      </div>
    </Modal>
  );
};
