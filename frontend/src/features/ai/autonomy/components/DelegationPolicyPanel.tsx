import React, { useState, useCallback } from 'react';
import { GitBranch, ChevronDown, ChevronRight } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { EntityLink } from '@/shared/components/entity';
import { useDelegationPolicies } from '../api/autonomyApi';
import type { DelegationPolicy } from '../types/autonomy';

const POLICY_VARIANT: Record<string, 'warning' | 'info' | 'success'> = {
  conservative: 'warning',
  moderate: 'info',
  permissive: 'success',
};

const PolicyRow: React.FC<{
  policy: DelegationPolicy;
  isExpanded: boolean;
  onToggle: () => void;
}> = ({ policy, isExpanded, onToggle }) => (
  <div className="rounded-lg bg-theme-surface border border-theme overflow-hidden">
    {/* Collapsed header */}
    <div
      onClick={onToggle}
      className="flex items-center justify-between p-3 cursor-pointer hover:bg-theme-background/50 transition-colors"
    >
      <div className="flex items-center gap-2 min-w-0">
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onToggle(); }}
          className="p-1 text-theme-secondary hover:text-theme-primary shrink-0"
          title={isExpanded ? 'Collapse' : 'Expand'}
        >
          {isExpanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
        </button>
        <GitBranch className="h-4 w-4 text-theme-tertiary shrink-0" />
        <EntityLink type="agent" id={policy.agent_id} label={policy.agent_name} className="text-sm font-medium" />
      </div>
      <Badge variant={POLICY_VARIANT[policy.inheritance_policy] || 'info'} size="sm">
        {policy.inheritance_policy}
      </Badge>
    </div>

    {/* Expanded own-detail */}
    {isExpanded && (
      <div className="border-t border-theme p-3 bg-theme-background space-y-3">
        <div className="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
          <div>
            <p className="text-xs text-theme-tertiary">Max Depth</p>
            <p className="text-theme-primary font-medium">{policy.max_depth}</p>
          </div>
          <div>
            <p className="text-xs text-theme-tertiary">Budget Share</p>
            <p className="text-theme-primary font-medium">{Math.round(policy.budget_delegation_pct * 100)}%</p>
          </div>
          <div>
            <p className="text-xs text-theme-tertiary">Inheritance</p>
            <p className="text-theme-primary font-medium capitalize">{policy.inheritance_policy}</p>
          </div>
          <div>
            <p className="text-xs text-theme-tertiary">Delegatable Actions</p>
            <p className="text-theme-primary font-medium">{policy.delegatable_actions.length || 'All'}</p>
          </div>
          {policy.created_at && (
            <div>
              <p className="text-xs text-theme-tertiary">Created</p>
              <p className="text-theme-primary font-medium">{new Date(policy.created_at).toLocaleString()}</p>
            </div>
          )}
        </div>

        {policy.delegatable_actions.length > 0 && (
          <div>
            <p className="text-xs text-theme-tertiary mb-1">Actions</p>
            <div className="flex gap-1 flex-wrap">
              {policy.delegatable_actions.map(a => (
                <span key={a} className="px-1.5 py-0.5 text-[10px] rounded bg-theme-surface border border-theme text-theme-secondary">
                  {a}
                </span>
              ))}
            </div>
          </div>
        )}

        {policy.allowed_delegate_types.length > 0 && (
          <div>
            <p className="text-xs text-theme-tertiary mb-1">Allowed Delegate Types</p>
            <div className="flex gap-1 flex-wrap">
              {policy.allowed_delegate_types.map(t => (
                <span key={t} className="px-1.5 py-0.5 text-[10px] rounded bg-theme-background-secondary text-theme-tertiary">
                  {t}
                </span>
              ))}
            </div>
          </div>
        )}
      </div>
    )}
  </div>
);

export const DelegationPolicyPanel: React.FC = () => {
  const { data: policies, isLoading } = useDelegationPolicies();
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

  const toggleExpand = useCallback((id: string) => {
    setExpandedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }, []);

  if (isLoading) return null;

  return (
    <Card>
      <CardHeader title="Delegation Policies" />
      <CardContent>
        {policies && policies.length > 0 ? (
          <div className="space-y-2">
            {policies.map(p => (
              <PolicyRow
                key={p.id}
                policy={p}
                isExpanded={expandedIds.has(p.id)}
                onToggle={() => toggleExpand(p.id)}
              />
            ))}
          </div>
        ) : (
          <div className="py-6 text-center text-theme-tertiary">
            <GitBranch className="w-10 h-10 mx-auto mb-2 opacity-30" />
            <p className="text-sm">No delegation policies configured</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
