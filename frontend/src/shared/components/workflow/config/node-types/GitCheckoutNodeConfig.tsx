import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import type { NodeTypeConfigProps } from './types';

export const GitCheckoutNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <Input
        label="Repository"
        value={config.configuration.repository || ''}
        onChange={(e) => handleConfigChange('repository', e.target.value)}
        placeholder="{{trigger.repository}} or owner/repo"
        description="Repository path or variable from trigger context"
      />

      <Input
        label="Git Reference (Branch/Tag/SHA)"
        value={config.configuration.ref || ''}
        onChange={(e) => handleConfigChange('ref', e.target.value)}
        placeholder="{{trigger.ref}}, main, v1.0.0, or SHA"
        description="Branch name, tag, or commit SHA to checkout"
      />

      <Input
        label="Fetch Depth"
        type="number"
        value={config.configuration.fetch_depth ?? 1}
        onChange={(e) => handleConfigChange('fetch_depth', parseInt(e.target.value) || 0)}
        min={0}
        description="Shallow clone depth (0 for full history)"
      />

      <div className="space-y-3 pt-2">
        <Checkbox
          label="Checkout Submodules"
          description="Initialize and checkout git submodules"
          checked={config.configuration.submodules === true}
          onCheckedChange={(checked) => handleConfigChange('submodules', checked)}
        />

        <Checkbox
          label="Enable Git LFS"
          description="Fetch large files tracked by Git LFS"
          checked={config.configuration.lfs === true}
          onCheckedChange={(checked) => handleConfigChange('lfs', checked)}
        />

        <Checkbox
          label="Clean Checkout"
          description="Remove untracked files before checkout"
          checked={config.configuration.clean === true}
          onCheckedChange={(checked) => handleConfigChange('clean', checked)}
        />
      </div>

      <Input
        label="Checkout Path"
        value={config.configuration.checkout_path || ''}
        onChange={(e) => handleConfigChange('checkout_path', e.target.value)}
        placeholder="Leave empty for auto-generated path"
        description="Custom directory path for the checkout"
      />

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">checkout_path</code> - Path to checked out code</li>
          <li><code className="text-theme-accent">sha</code> - Full commit SHA</li>
          <li><code className="text-theme-accent">ref</code> - Resolved reference</li>
        </ul>
      </div>
    </div>
  );
};
