import React from 'react';
import { Zap } from 'lucide-react';
import { RoutingDecision } from '@/shared/services/ai/ModelRouterApiService';

interface DecisionsTabProps {
  decisions: RoutingDecision[];
  getDecisionColor: (outcome: string) => string;
}

export const DecisionsTab: React.FC<DecisionsTabProps> = ({ decisions, getDecisionColor }) => {
  if (decisions.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Zap size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No routing decisions</h3>
        <p className="text-theme-secondary">Routing decisions will appear as requests are processed</p>
      </div>
    );
  }

  return (
    <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
      <table className="w-full">
        <thead>
          <tr className="border-b border-theme bg-theme-bg">
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Decision</th>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Strategy</th>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Provider</th>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Outcome</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-theme-secondary uppercase">Latency</th>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Time</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-theme">
          {decisions.map(decision => (
            <tr key={decision.id} className="hover:bg-theme-surface-hover transition-colors">
              <td className="px-4 py-3 text-sm font-mono text-theme-primary">{decision.id.slice(0, 8)}</td>
              <td className="px-4 py-3 text-sm text-theme-primary">{decision.strategy_used || '-'}</td>
              <td className="px-4 py-3 text-sm text-theme-primary">{decision.selected_provider?.name || '-'}</td>
              <td className="px-4 py-3">
                <span className={`px-2 py-1 text-xs rounded ${getDecisionColor(decision.outcome)}`}>
                  {decision.outcome}
                </span>
              </td>
              <td className="px-4 py-3 text-sm text-right text-theme-secondary">
                {decision.performance?.latency_ms ? `${decision.performance.latency_ms}ms` : '-'}
              </td>
              <td className="px-4 py-3 text-sm text-theme-secondary">
                {new Date(decision.created_at).toLocaleString()}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};
