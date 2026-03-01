import React from 'react';
import { Settings, GitBranch, GitMerge, Trash2 } from 'lucide-react';
import type { ParallelSessionDetail } from '../types';

interface ConfigurationPanelProps {
  session: ParallelSessionDetail;
}

export const ConfigurationPanel: React.FC<ConfigurationPanelProps> = ({ session }) => {
  const configItems = [
    { icon: GitBranch, label: 'Repository', value: session.repository_path },
    { icon: GitBranch, label: 'Base Branch', value: session.base_branch },
    { icon: GitMerge, label: 'Merge Strategy', value: session.merge_strategy },
    { icon: Settings, label: 'Max Parallel', value: String(session.max_parallel) },
    { icon: Trash2, label: 'Auto Cleanup', value: session.configuration?.auto_cleanup !== false ? 'Enabled' : 'Disabled' },
  ];

  if (session.integration_branch) {
    configItems.push({ icon: GitBranch, label: 'Integration Branch', value: session.integration_branch });
  }

  return (
    <div className="space-y-4">
      <h3 className="text-sm font-medium text-theme-text-primary">Session Configuration</h3>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {configItems.map((item) => (
          <div key={item.label} className="flex items-start gap-3 p-3 bg-theme-bg-primary border border-theme rounded-lg">
            <item.icon className="w-4 h-4 text-theme-text-secondary flex-shrink-0 mt-0.5" />
            <div className="min-w-0">
              <div className="text-xs text-theme-text-secondary">{item.label}</div>
              <div className="text-sm text-theme-text-primary truncate">{item.value}</div>
            </div>
          </div>
        ))}
      </div>

      {session.metadata && Object.keys(session.metadata).length > 0 && (
        <div>
          <h4 className="text-xs font-medium text-theme-text-secondary mb-2">Metadata</h4>
          <pre className="text-xs text-theme-text-secondary bg-theme-bg-tertiary p-3 rounded-lg overflow-x-auto">
            {JSON.stringify(session.metadata, null, 2)}
          </pre>
        </div>
      )}
    </div>
  );
};
