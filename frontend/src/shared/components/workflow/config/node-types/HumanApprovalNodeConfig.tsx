import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const HumanApprovalNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <Input
        label="Approval Title"
        value={config.configuration.title || ''}
        onChange={(e) => handleConfigChange('title', e.target.value)}
        placeholder="Approval required for..."
      />
      <Textarea
        label="Description"
        value={config.configuration.approval_description || ''}
        onChange={(e) => handleConfigChange('approval_description', e.target.value)}
        placeholder="Please review and approve the following..."
        rows={3}
      />
      <Input
        label="Approver Email/Role"
        value={config.configuration.approver || ''}
        onChange={(e) => handleConfigChange('approver', e.target.value)}
        placeholder="admin@example.com or role:manager"
      />
      <Input
        label="Timeout (hours)"
        type="number"
        value={config.configuration.timeout_hours || 24}
        onChange={(e) => handleConfigChange('timeout_hours', parseInt(e.target.value) || 24)}
      />
    </div>
  );
};
