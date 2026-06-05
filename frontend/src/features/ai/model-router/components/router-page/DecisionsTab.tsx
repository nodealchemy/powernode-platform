import React, { useState, useCallback } from 'react';
import { Zap, ChevronRight, ChevronDown } from 'lucide-react';
import { RoutingDecision } from '@/shared/services/ai/ModelRouterApiService';
import { EntityLink } from '@/shared/components/entity';

interface DecisionsTabProps {
  decisions: RoutingDecision[];
  getDecisionColor: (outcome: string) => string;
}

const DecisionDetailRow: React.FC<{ decision: RoutingDecision }> = ({ decision }) => (
  <tr className="bg-theme-background border-b border-theme">
    <td className="px-4 py-3" />
    <td colSpan={5} className="px-4 py-3">
      <div className="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
        <DetailItem label="Request Type" value={decision.request_type || '—'} />
        <DetailItem label="Candidates Evaluated" value={String(decision.candidates_evaluated ?? '—')} />
        <DetailItem label="Outcome" value={decision.outcome} />
        {decision.routing_rule?.name && (
          <DetailItem label="Routing Rule" value={decision.routing_rule.name} />
        )}
        {decision.cost?.estimated != null && (
          <DetailItem label="Est. Cost" value={`$${decision.cost.estimated.toFixed(4)}`} />
        )}
        {decision.cost?.actual != null && (
          <DetailItem label="Actual Cost" value={`$${decision.cost.actual.toFixed(4)}`} />
        )}
        {decision.cost?.savings != null && (
          <DetailItem label="Savings" value={`$${decision.cost.savings.toFixed(4)}`} />
        )}
        {decision.performance?.actual_tokens != null && (
          <DetailItem label="Tokens" value={decision.performance.actual_tokens.toLocaleString()} />
        )}
        {decision.performance?.quality_score != null && (
          <DetailItem label="Quality Score" value={decision.performance.quality_score.toFixed(2)} />
        )}
        {decision.decision_reason && (
          <div className="col-span-2 md:col-span-3">
            <p className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-1">Decision Reason</p>
            <p className="text-sm text-theme-secondary">{decision.decision_reason}</p>
          </div>
        )}
        {decision.scoring_breakdown && Object.keys(decision.scoring_breakdown).length > 0 && (
          <div className="col-span-2 md:col-span-3">
            <p className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-1">Scoring Breakdown</p>
            <pre className="text-xs bg-theme-surface p-2 rounded overflow-x-auto font-mono text-theme-primary">
              {JSON.stringify(decision.scoring_breakdown, null, 2)}
            </pre>
          </div>
        )}
      </div>
    </td>
  </tr>
);

const DetailItem: React.FC<{ label: string; value: string }> = ({ label, value }) => (
  <div>
    <p className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-0.5">{label}</p>
    <p className="text-sm text-theme-primary">{value}</p>
  </div>
);

export const DecisionsTab: React.FC<DecisionsTabProps> = ({ decisions, getDecisionColor }) => {
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());

  const toggleExpand = useCallback((id: string) => {
    setExpandedRows(prev => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

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
          <tr className="border-b border-theme bg-theme-surface">
            <th className="w-10 px-4 py-3" />
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Decision</th>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Strategy</th>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Provider</th>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Outcome</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-theme-secondary uppercase">Latency</th>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Time</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-theme">
          {decisions.map(decision => {
            const isExpanded = expandedRows.has(decision.id);
            return (
              <React.Fragment key={decision.id}>
                <tr
                  className="hover:bg-theme-surface-hover transition-colors cursor-pointer"
                  onClick={() => toggleExpand(decision.id)}
                >
                  <td className="px-4 py-3">
                    <button
                      type="button"
                      className="p-1 text-theme-secondary hover:text-theme-primary"
                      aria-label={isExpanded ? 'Collapse row' : 'Expand row'}
                    >
                      {isExpanded ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
                    </button>
                  </td>
                  <td className="px-4 py-3 text-sm font-mono text-theme-primary">{decision.id.slice(0, 8)}</td>
                  <td className="px-4 py-3 text-sm text-theme-primary">{decision.strategy_used || '-'}</td>
                  <td className="px-4 py-3 text-sm text-theme-primary">
                    {decision.selected_provider?.id ? (
                      <EntityLink
                        type="ai_provider"
                        id={decision.selected_provider.id}
                        label={decision.selected_provider.name}
                      />
                    ) : (
                      decision.selected_provider?.name || '-'
                    )}
                  </td>
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
                {isExpanded && <DecisionDetailRow decision={decision} />}
              </React.Fragment>
            );
          })}
        </tbody>
      </table>
    </div>
  );
};
