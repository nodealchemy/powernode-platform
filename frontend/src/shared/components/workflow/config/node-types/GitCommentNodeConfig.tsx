import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const GitCommentNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <EnhancedSelect
        label="Target Type"
        value={config.configuration.target_type || 'pull_request'}
        onChange={(value) => handleConfigChange('target_type', value)}
        options={[
          { value: 'pull_request', label: 'Pull Request' },
          { value: 'issue', label: 'Issue' },
          { value: 'commit', label: 'Commit' }
        ]}
      />

      <Input
        label="Target Number / SHA"
        value={config.configuration.target_number || ''}
        onChange={(e) => handleConfigChange('target_number', e.target.value)}
        placeholder="{{trigger.pull_request.number}}, {{pr_number}}, or 123"
        description={
          config.configuration.target_type === 'commit'
            ? 'Commit SHA to comment on'
            : 'PR or Issue number to comment on'
        }
        required
      />

      <Textarea
        label="Comment Body"
        value={config.configuration.comment_body || ''}
        onChange={(e) => handleConfigChange('comment_body', e.target.value)}
        placeholder="## Automated Comment&#10;&#10;Build status: **{{build_status}}**&#10;&#10;[View Details]({{build_url}})"
        rows={8}
        description="Markdown content for the comment (supports {{variables}})"
        required
      />

      <EnhancedSelect
        label="Comment Template"
        value={config.configuration.template || 'custom'}
        onChange={(value) => {
          handleConfigChange('template', value);
          // Auto-fill template content
          if (value !== 'custom') {
            const templates: Record<string, string> = {
              build_success: '## Build Successful\n\n:white_check_mark: All checks passed!\n\n**Commit:** `{{sha}}`\n**Duration:** {{duration}}',
              build_failure: '## Build Failed\n\n:x: The build has failed.\n\n**Commit:** `{{sha}}`\n**Error:** {{error_message}}\n\n[View Logs]({{logs_url}})',
              deploy_complete: '## Deployment Complete\n\n:rocket: Successfully deployed to **{{environment}}**\n\n**Version:** {{version}}\n**URL:** {{deploy_url}}',
              test_results: '## Test Results\n\n**Passed:** {{passed}} | **Failed:** {{failed}} | **Skipped:** {{skipped}}\n\n**Coverage:** {{coverage}}%',
            };
            handleConfigChange('comment_body', templates[value] || '');
          }
        }}
        options={[
          { value: 'custom', label: 'Custom Template' },
          { value: 'build_success', label: 'Build Success' },
          { value: 'build_failure', label: 'Build Failure' },
          { value: 'deploy_complete', label: 'Deployment Complete' },
          { value: 'test_results', label: 'Test Results' }
        ]}
      />

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
          <li><code className="text-theme-accent">comment_id</code> - ID of the created comment</li>
          <li><code className="text-theme-accent">comment_url</code> - URL to the comment</li>
          <li><code className="text-theme-accent">comment_posted</code> - Boolean success status</li>
        </ul>
      </div>

      <div className="p-3 bg-theme-surface rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Available Variables:</strong>
        </p>
        <p className="text-xs text-theme-muted mt-1">
          Use <code className="text-theme-accent">{'{{variable_name}}'}</code> syntax to reference values from previous nodes or trigger context.
        </p>
        <p className="text-xs text-theme-muted mt-1">
          Common: <code>sha</code>, <code>ref</code>, <code>branch_name</code>, <code>pr_number</code>, <code>build_status</code>, <code>test_results</code>
        </p>
      </div>
    </div>
  );
};
