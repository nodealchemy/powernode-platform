import React from 'react';
import { ShieldCheck } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { useCapabilityMatrix } from '../api/autonomyApi';
import type { CapabilityPolicy } from '../types/autonomy';

const POLICY_COLORS: Record<CapabilityPolicy, string> = {
  allowed: 'bg-theme-success text-white',
  requires_approval: 'bg-theme-warning text-white',
  denied: 'bg-theme-error text-white',
};

const POLICY_LABELS: Record<CapabilityPolicy, string> = {
  allowed: 'Allow',
  requires_approval: 'Approval',
  denied: 'Deny',
};

const TIER_ORDER = ['supervised', 'monitored', 'trusted', 'autonomous'];

export const CapabilityMatrixViewer: React.FC = () => {
  const { data: matrix, isLoading } = useCapabilityMatrix();

  if (isLoading || !matrix) return null;

  const actionTypes = Object.keys(matrix[TIER_ORDER[0]] || {});

  return (
    <Card>
      <CardHeader title="Capability Matrix" />
      <CardContent>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-theme-border">
                <th className="text-left py-2 px-2 text-theme-muted font-medium">Action</th>
                {TIER_ORDER.map(tier => (
                  <th key={tier} className="text-center py-2 px-2 text-theme-muted font-medium capitalize">
                    {tier}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {actionTypes.map(action => (
                <tr key={action} className="border-b border-theme-border last:border-0">
                  <td className="py-2 px-2 text-theme-primary font-medium">
                    {action.replace(/_/g, ' ')}
                  </td>
                  {TIER_ORDER.map(tier => {
                    const policy = (matrix[tier]?.[action] || 'denied') as CapabilityPolicy;
                    return (
                      <td key={tier} className="py-2 px-2 text-center">
                        <span className={`inline-block px-2 py-0.5 rounded text-[10px] font-medium ${POLICY_COLORS[policy]}`}>
                          {POLICY_LABELS[policy]}
                        </span>
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {actionTypes.length === 0 && (
          <div className="py-6 text-center text-theme-muted">
            <ShieldCheck className="w-10 h-10 mx-auto mb-2 opacity-30" />
            <p className="text-sm">No capability matrix configured</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
