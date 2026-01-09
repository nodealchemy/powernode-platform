import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import type { NodeTypeConfigProps } from './types';

export const GitPullRequestNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <Input
        label="PR Title"
        value={config.configuration.title || ''}
        onChange={(e) => handleConfigChange('title', e.target.value)}
        placeholder="feat: {{trigger.commit_message}}"
        description="Title for the pull request"
        required
      />

      <Textarea
        label="PR Description"
        value={config.configuration.body || ''}
        onChange={(e) => handleConfigChange('body', e.target.value)}
        placeholder="## Summary&#10;Describe your changes...&#10;&#10;## Changes&#10;- Change 1&#10;- Change 2"
        rows={6}
        description="Markdown description for the PR body"
      />

      <Input
        label="Head Branch (Source)"
        value={config.configuration.head || ''}
        onChange={(e) => handleConfigChange('head', e.target.value)}
        placeholder="{{branch_name}} or feature/my-feature"
        description="Branch containing the changes"
        required
      />

      <Input
        label="Base Branch (Target)"
        value={config.configuration.base || ''}
        onChange={(e) => handleConfigChange('base', e.target.value)}
        placeholder="main"
        description="Branch to merge into (default: main)"
      />

      <Input
        label="Labels"
        value={
          Array.isArray(config.configuration.labels)
            ? config.configuration.labels.join(', ')
            : config.configuration.labels || ''
        }
        onChange={(e) => {
          const labels = e.target.value
            .split(',')
            .map((l: string) => l.trim())
            .filter(Boolean);
          handleConfigChange('labels', labels);
        }}
        placeholder="enhancement, automated, needs-review"
        description="Comma-separated list of labels"
      />

      <Input
        label="Reviewers"
        value={
          Array.isArray(config.configuration.reviewers)
            ? config.configuration.reviewers.join(', ')
            : config.configuration.reviewers || ''
        }
        onChange={(e) => {
          const reviewers = e.target.value
            .split(',')
            .map((r: string) => r.trim())
            .filter(Boolean);
          handleConfigChange('reviewers', reviewers);
        }}
        placeholder="username1, username2"
        description="Comma-separated list of reviewer usernames"
      />

      <Input
        label="Assignees"
        value={
          Array.isArray(config.configuration.assignees)
            ? config.configuration.assignees.join(', ')
            : config.configuration.assignees || ''
        }
        onChange={(e) => {
          const assignees = e.target.value
            .split(',')
            .map((a: string) => a.trim())
            .filter(Boolean);
          handleConfigChange('assignees', assignees);
        }}
        placeholder="username1, username2"
        description="Comma-separated list of assignee usernames"
      />

      <div className="space-y-3 pt-2">
        <Checkbox
          label="Create as Draft"
          description="Create the PR as a draft (not ready for review)"
          checked={config.configuration.draft === true}
          onCheckedChange={(checked) => handleConfigChange('draft', checked)}
        />

        <Checkbox
          label="Auto-Merge When Ready"
          description="Enable auto-merge when all requirements are met"
          checked={config.configuration.auto_merge === true}
          onCheckedChange={(checked) => handleConfigChange('auto_merge', checked)}
        />

        <Checkbox
          label="Allow Maintainer Edits"
          description="Allow maintainers to modify the PR branch"
          checked={config.configuration.maintainer_can_modify !== false}
          onCheckedChange={(checked) => handleConfigChange('maintainer_can_modify', checked)}
        />
      </div>

      <Input
        label="Repository ID"
        value={config.configuration.repository_id || ''}
        onChange={(e) => handleConfigChange('repository_id', e.target.value)}
        placeholder="{{trigger.repository_id}}"
        description="UUID of the connected git repository"
      />

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">pr_number</code> - Pull request number</li>
          <li><code className="text-theme-accent">pr_url</code> - URL to the pull request</li>
          <li><code className="text-theme-accent">pr_id</code> - Pull request ID</li>
          <li><code className="text-theme-accent">state</code> - PR state (open, closed, merged)</li>
        </ul>
      </div>
    </div>
  );
};
