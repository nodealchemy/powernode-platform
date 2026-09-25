import React from 'react';
import { Eye } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EntityLink } from '@/shared/components/entity';
import { governanceApi, CollusionIndicator } from '@/shared/services/ai/GovernanceApiService';

function getCollusionTypeLabel(type: string): string {
  switch (type) {
    case 'synchronized_output': return 'Synchronized Output';
    case 'mutual_approval': return 'Mutual Approval';
    case 'resource_hoarding': return 'Resource Hoarding';
    case 'trust_inflation': return 'Trust Inflation';
    case 'echo_chamber': return 'Echo Chamber';
    default: return type;
  }
}

const CollusionContent: React.FC<{ indicators: CollusionIndicator[]; loading: boolean }> = ({ indicators, loading }) => {
  if (loading) return <LoadingSpinner size="sm" className="py-8" />;
  if (indicators.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Eye size={48} className="mx-auto text-theme-success-fg mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No collusion indicators</h3>
        <p className="text-theme-secondary">Multi-agent collusion detection has not found suspicious patterns</p>
      </div>
    );
  }
  return (
    <div className="space-y-4">
      {indicators.map(indicator => (
        <div key={indicator.id} data-testid="collusion-card" className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-3">
              <span className={`px-2 py-1 text-xs rounded ${indicator.correlation_score >= 0.7 ? 'text-theme-error-fg bg-theme-error-fg/10' : 'text-theme-warning-fg bg-theme-warning-fg/10'}`}>
                {(indicator.correlation_score * 100).toFixed(0)}% correlation
              </span>
              <span className="font-medium text-theme-primary">{getCollusionTypeLabel(indicator.indicator_type)}</span>
            </div>
            <span className="text-sm text-theme-secondary">{new Date(indicator.created_at).toLocaleDateString()}</span>
          </div>
          {indicator.agent_cluster.length > 0 && (
            <div className="flex items-center gap-2 mt-2">
              <span className="text-xs text-theme-secondary">Agents involved:</span>
              <div className="flex flex-wrap gap-1">
                {indicator.agent_cluster.map((agentId, idx) => (
                  <span key={idx} className="px-2 py-0.5 text-xs bg-theme-interactive-primary/10 text-theme-interactive-primary rounded">
                    {typeof agentId === 'string'
                      ? <EntityLink type="agent" id={agentId} label={agentId.slice(0, 8)} />
                      : agentId}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      ))}
    </div>
  );
};

/** Multi-agent collusion indicators (Compliance Audit → Collusion). */
export const CollusionPanel: React.FC = () => {
  const { data: indicators = [], isLoading } = useQuery({
    queryKey: ['control', 'collusion-indicators'],
    queryFn: async () => (await governanceApi.getCollusionIndicators()).items ?? [],
  });
  return <CollusionContent indicators={indicators} loading={isLoading} />;
};
