import React from 'react';
import { Shield } from 'lucide-react';
import { cn } from '@/shared/utils/cn';
import { AutonomyConfigResponse } from '../services/agentTeamsApi';

const BoolBadge: React.FC<{ value: boolean }> = ({ value }) => (
  <span className={cn(
    'text-xs font-medium px-1.5 py-0.5 rounded',
    value ? 'bg-theme-success/10 text-theme-success' : 'bg-theme-accent text-theme-secondary'
  )}>
    {value ? 'Yes' : 'No'}
  </span>
);

interface AutonomyConfigProps {
  autonomyConfig: AutonomyConfigResponse;
}

export const AutonomyConfig: React.FC<AutonomyConfigProps> = ({ autonomyConfig }) => {
  return (
    <div className="bg-theme-background border border-theme rounded-lg p-4 space-y-3">
      <h4 className="text-sm font-semibold text-theme-primary flex items-center gap-2">
        <Shield size={16} />
        Autonomy Config
      </h4>
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-xs text-theme-secondary">Level</span>
          <span className="text-xs text-theme-primary font-medium capitalize">
            {autonomyConfig.autonomy_level.replace('_', ' ')}
          </span>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-xs text-theme-secondary">Max Agents</span>
          <span className="text-xs text-theme-primary font-medium">{autonomyConfig.max_agents_per_team}</span>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-xs text-theme-secondary">Agent Creation</span>
          <BoolBadge value={autonomyConfig.allow_agent_creation} />
        </div>
        <div className="flex items-center justify-between">
          <span className="text-xs text-theme-secondary">Cross-Team Ops</span>
          <BoolBadge value={autonomyConfig.allow_cross_team_ops} />
        </div>
        <div className="flex items-center justify-between">
          <span className="text-xs text-theme-secondary">Human Approval</span>
          <BoolBadge value={autonomyConfig.require_human_approval} />
        </div>
        <div className="flex items-center justify-between">
          <span className="text-xs text-theme-secondary">Branch Protection</span>
          <BoolBadge value={autonomyConfig.branch_protection_enabled} />
        </div>
      </div>
    </div>
  );
};
