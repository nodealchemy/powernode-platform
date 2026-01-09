import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import type { NodeTypeConfigProps } from './types';

export const GitBranchNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <Input
        label="Branch Name"
        value={config.configuration.branch_name || ''}
        onChange={(e) => handleConfigChange('branch_name', e.target.value)}
        placeholder="feature/{{trigger.issue_number}}-description"
        description="Name of the branch to create or switch to"
        required
      />

      <Input
        label="Base Branch"
        value={config.configuration.base_branch || ''}
        onChange={(e) => handleConfigChange('base_branch', e.target.value)}
        placeholder="main"
        description="Branch to create from (default: main)"
      />

      <div className="space-y-3 pt-2">
        <Checkbox
          label="Create If Missing"
          description="Create the branch if it doesn't exist"
          checked={config.configuration.create_if_missing !== false}
          onCheckedChange={(checked) => handleConfigChange('create_if_missing', checked)}
        />

        <Checkbox
          label="Force Create"
          description="Reset branch to base if it already exists"
          checked={config.configuration.force === true}
          onCheckedChange={(checked) => handleConfigChange('force', checked)}
        />

        <Checkbox
          label="Push to Remote"
          description="Push the branch to remote after creation"
          checked={config.configuration.push_to_remote === true}
          onCheckedChange={(checked) => handleConfigChange('push_to_remote', checked)}
        />
      </div>

      <Input
        label="Working Directory"
        value={config.configuration.checkout_path || ''}
        onChange={(e) => handleConfigChange('checkout_path', e.target.value)}
        placeholder="{{checkout_path}}"
        description="Path to the git repository"
      />

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">branch_name</code> - Name of the created/switched branch</li>
          <li><code className="text-theme-accent">base_branch</code> - The base branch used</li>
          <li><code className="text-theme-accent">ref</code> - Current branch reference</li>
        </ul>
      </div>
    </div>
  );
};
