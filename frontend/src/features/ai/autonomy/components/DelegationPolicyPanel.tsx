import React from 'react';
import { GitBranch } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { useDelegationPolicies } from '../api/autonomyApi';
import type { DelegationPolicy } from '../types/autonomy';

const POLICY_VARIANT: Record<string, 'warning' | 'info' | 'success'> = {
  conservative: 'warning',
  moderate: 'info',
  permissive: 'success',
};

const PolicyRow: React.FC<{ policy: DelegationPolicy }> = ({ policy }) => (
  <div className="p-3 rounded-lg bg-theme-surface border border-theme-border">
    <div className="flex items-center justify-between mb-2">
      <div className="flex items-center gap-2">
        <GitBranch className="h-4 w-4 text-theme-muted" />
        <span className="text-sm font-medium text-theme-primary">{policy.agent_name}</span>
      </div>
      <Badge variant={POLICY_VARIANT[policy.inheritance_policy] || 'info'} size="sm">
        {policy.inheritance_policy}
      </Badge>
    </div>
    <div className="grid grid-cols-3 gap-2 text-xs text-theme-muted">
      <div>
        <span className="text-theme-secondary">Max Depth:</span> {policy.max_depth}
      </div>
      <div>
        <span className="text-theme-secondary">Budget Share:</span> {Math.round(policy.budget_delegation_pct * 100)}%
      </div>
      <div>
        <span className="text-theme-secondary">Actions:</span> {policy.delegatable_actions.length || 'All'}
      </div>
    </div>
    {policy.allowed_delegate_types.length > 0 && (
      <div className="mt-2 flex gap-1 flex-wrap">
        {policy.allowed_delegate_types.map(t => (
          <span key={t} className="px-1.5 py-0.5 text-[10px] rounded bg-theme-bg-secondary text-theme-muted">
            {t}
          </span>
        ))}
      </div>
    )}
  </div>
);

export const DelegationPolicyPanel: React.FC = () => {
  const { data: policies, isLoading } = useDelegationPolicies();

  if (isLoading) return null;

  return (
    <Card>
      <CardHeader title="Delegation Policies" />
      <CardContent>
        {policies && policies.length > 0 ? (
          <div className="space-y-2">
            {policies.map(p => <PolicyRow key={p.id} policy={p} />)}
          </div>
        ) : (
          <div className="py-6 text-center text-theme-muted">
            <GitBranch className="w-10 h-10 mx-auto mb-2 opacity-30" />
            <p className="text-sm">No delegation policies configured</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
