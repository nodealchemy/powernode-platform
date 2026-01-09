import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const DeployNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const environment = config.configuration.environment || 'staging';
  const showCustomEnv = environment === 'custom';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <EnhancedSelect
        label="Environment"
        value={environment}
        onChange={(value) => handleConfigChange('environment', value)}
        options={[
          { value: 'development', label: 'Development' },
          { value: 'staging', label: 'Staging' },
          { value: 'production', label: 'Production' },
          { value: 'custom', label: 'Custom' }
        ]}
      />

      {showCustomEnv && (
        <Input
          label="Custom Environment Name"
          value={config.configuration.custom_environment || ''}
          onChange={(e) => handleConfigChange('custom_environment', e.target.value)}
          placeholder="e.g., qa, preview, canary-test"
        />
      )}

      <EnhancedSelect
        label="Deployment Strategy"
        value={config.configuration.strategy || 'rolling'}
        onChange={(value) => handleConfigChange('strategy', value)}
        options={[
          { value: 'rolling', label: 'Rolling Update' },
          { value: 'blue_green', label: 'Blue/Green' },
          { value: 'canary', label: 'Canary' },
          { value: 'recreate', label: 'Recreate' }
        ]}
      />

      <Input
        label="Version / Git Ref"
        value={config.configuration.version || ''}
        onChange={(e) => handleConfigChange('version', e.target.value)}
        placeholder="{{sha}}, {{ref}}, or specific version"
        description="Leave empty to use current checkout ref"
      />

      <Input
        label="Replicas"
        type="number"
        value={config.configuration.replicas || 1}
        onChange={(e) => handleConfigChange('replicas', parseInt(e.target.value) || 1)}
        min={1}
      />

      <Input
        label="Health Check Path"
        value={config.configuration.health_check_path || ''}
        onChange={(e) => handleConfigChange('health_check_path', e.target.value)}
        placeholder="/health or /api/health"
      />

      <Input
        label="Deployment Timeout (seconds)"
        type="number"
        value={config.configuration.timeout_seconds || 600}
        onChange={(e) => handleConfigChange('timeout_seconds', parseInt(e.target.value) || 600)}
        min={30}
        max={3600}
        description="Max time for deployment to complete"
      />

      <div className="space-y-3 pt-2">
        <Checkbox
          label="Wait for Completion"
          description="Wait for deployment to complete before continuing"
          checked={config.configuration.wait_for_completion !== false}
          onCheckedChange={(checked) => handleConfigChange('wait_for_completion', checked)}
        />

        <Checkbox
          label="Rollback on Failure"
          description="Automatically rollback if deployment fails"
          checked={config.configuration.rollback_on_failure !== false}
          onCheckedChange={(checked) => handleConfigChange('rollback_on_failure', checked)}
        />
      </div>

      <Textarea
        label="Pre-Deploy Script"
        value={config.configuration.pre_deploy_script || ''}
        onChange={(e) => handleConfigChange('pre_deploy_script', e.target.value)}
        placeholder="Commands to run before deployment..."
        rows={3}
      />

      <Textarea
        label="Post-Deploy Script"
        value={config.configuration.post_deploy_script || ''}
        onChange={(e) => handleConfigChange('post_deploy_script', e.target.value)}
        placeholder="Commands to run after deployment..."
        rows={3}
      />
    </div>
  );
};
