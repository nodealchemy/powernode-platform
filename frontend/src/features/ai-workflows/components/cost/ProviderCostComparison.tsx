import React, { useMemo } from 'react';
import { TrendingUp, TrendingDown, Zap, DollarSign, CheckCircle2, AlertCircle } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import type { CostMetrics } from './CostOptimizationDashboard';

interface ProviderComparison {
  provider: string;
  cost: number;
  tokens: number;
  cost_per_1k_tokens: number;
  execution_count: number;
  avg_cost_per_execution: number;
  model_count: number;
  cost_trend: 'up' | 'down' | 'stable';
  reliability_score: number; // 0-100
  performance_score: number; // 0-100
}

export interface ProviderScores {
  [provider: string]: {
    reliability_score: number;
    performance_score: number;
  };
}

interface ProviderCostComparisonProps {
  metrics: CostMetrics;
  providerScores?: ProviderScores;
  onProviderSelect?: (provider: string) => void;
}

export const ProviderCostComparison: React.FC<ProviderCostComparisonProps> = ({
  metrics,
  providerScores,
  onProviderSelect
}) => {
  const providerComparisons = useMemo(() => {
    const comparisons: ProviderComparison[] = [];

    Object.entries(metrics.cost_by_provider).forEach(([provider, cost]) => {
      const tokens = metrics.tokens_by_provider[provider] || 0;
      const cost_per_1k_tokens = tokens > 0 ? (cost / tokens) * 1000 : 0;

      // Calculate execution count for this provider (from workflow data)
      const execution_count = Object.values(metrics.cost_by_workflow)
        .reduce((sum, workflow) => sum + workflow.executions, 0);

      const avg_cost_per_execution = execution_count > 0 ? cost / execution_count : 0;

      // Count models for this provider
      const model_count = Object.keys(metrics.cost_by_model)
        .filter(model => model.toLowerCase().includes(provider.toLowerCase()))
        .length;

      // Use provider scores if provided, otherwise use defaults
      const scores = providerScores?.[provider] || { reliability_score: 90, performance_score: 90 };
      const reliability_score = scores.reliability_score;
      const performance_score = scores.performance_score;

      comparisons.push({
        provider,
        cost,
        tokens,
        cost_per_1k_tokens,
        execution_count,
        avg_cost_per_execution,
        model_count,
        cost_trend: cost > metrics.total_cost * 0.4 ? 'up' : 'down',
        reliability_score,
        performance_score
      });
    });

    return comparisons.sort((a, b) => b.cost - a.cost);
  }, [metrics, providerScores]);

  const getTrendIcon = (trend: 'up' | 'down' | 'stable') => {
    if (trend === 'up') {
      return <TrendingUp className="h-4 w-4 text-theme-error" />;
    } else if (trend === 'down') {
      return <TrendingDown className="h-4 w-4 text-theme-success" />;
    }
    return null;
  };

  const getScoreBadge = (score: number) => {
    if (score >= 95) return <Badge variant="success" size="sm">Excellent</Badge>;
    if (score >= 85) return <Badge variant="info" size="sm">Good</Badge>;
    if (score >= 75) return <Badge variant="warning" size="sm">Fair</Badge>;
    return <Badge variant="outline" size="sm">Poor</Badge>;
  };

  const getProviderIcon = (provider: string) => {
    // Could be replaced with actual provider logos
    return (
      <div className="w-10 h-10 bg-theme-interactive-primary bg-opacity-10 rounded-lg flex items-center justify-center">
        <span className="text-theme-interactive-primary font-bold text-sm">
          {provider.charAt(0).toUpperCase()}
        </span>
      </div>
    );
  };

  const calculateEfficiency = (provider: ProviderComparison) => {
    // Efficiency = (Reliability * Performance) / Cost
    const efficiency = ((provider.reliability_score * provider.performance_score) / 10000) / provider.cost;
    return efficiency.toFixed(4);
  };

  const cheapestProvider = providerComparisons.reduce((min, p) =>
    p.cost_per_1k_tokens < min.cost_per_1k_tokens ? p : min
  , providerComparisons[0]);

  const mostReliableProvider = providerComparisons.reduce((max, p) =>
    p.reliability_score > max.reliability_score ? p : max
  , providerComparisons[0]);

  const mostEfficientProvider = providerComparisons.reduce((max, p) => {
    const currentEfficiency = parseFloat(calculateEfficiency(p));
    const maxEfficiency = parseFloat(calculateEfficiency(max));
    return currentEfficiency > maxEfficiency ? p : max;
  }, providerComparisons[0]);

  return (
    <div className="space-y-6">
      {/* Quick Insights */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 bg-theme-success bg-opacity-10 rounded-lg flex items-center justify-center">
              <DollarSign className="h-6 w-6 text-theme-success" />
            </div>
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Most Cost-Effective</p>
              <p className="font-semibold text-theme-primary capitalize">{cheapestProvider?.provider}</p>
              <p className="text-xs text-theme-success">
                ${cheapestProvider?.cost_per_1k_tokens.toFixed(4)}/1K tokens
              </p>
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
              <CheckCircle2 className="h-6 w-6 text-theme-info" />
            </div>
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Most Reliable</p>
              <p className="font-semibold text-theme-primary capitalize">{mostReliableProvider?.provider}</p>
              <p className="text-xs text-theme-info">
                {mostReliableProvider?.reliability_score}% uptime
              </p>
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 bg-theme-warning bg-opacity-10 rounded-lg flex items-center justify-center">
              <Zap className="h-6 w-6 text-theme-warning" />
            </div>
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Best Efficiency</p>
              <p className="font-semibold text-theme-primary capitalize">{mostEfficientProvider?.provider}</p>
              <p className="text-xs text-theme-warning">
                Score: {calculateEfficiency(mostEfficientProvider)}
              </p>
            </div>
          </div>
        </Card>
      </div>

      {/* Provider Comparison Table */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Provider Comparison</h3>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="border-b border-theme">
              <tr>
                <th className="text-left py-3 px-2 text-xs font-medium text-theme-tertiary uppercase">Provider</th>
                <th className="text-right py-3 px-2 text-xs font-medium text-theme-tertiary uppercase">Total Cost</th>
                <th className="text-right py-3 px-2 text-xs font-medium text-theme-tertiary uppercase">Cost/1K Tokens</th>
                <th className="text-right py-3 px-2 text-xs font-medium text-theme-tertiary uppercase">Executions</th>
                <th className="text-right py-3 px-2 text-xs font-medium text-theme-tertiary uppercase">Avg Cost/Exec</th>
                <th className="text-center py-3 px-2 text-xs font-medium text-theme-tertiary uppercase">Reliability</th>
                <th className="text-center py-3 px-2 text-xs font-medium text-theme-tertiary uppercase">Performance</th>
                <th className="text-center py-3 px-2 text-xs font-medium text-theme-tertiary uppercase">Trend</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {providerComparisons.map((provider) => (
                <tr
                  key={provider.provider}
                  className="hover:bg-theme-surface transition-colors cursor-pointer"
                  onClick={() => onProviderSelect?.(provider.provider)}
                >
                  <td className="py-4 px-2">
                    <div className="flex items-center gap-3">
                      {getProviderIcon(provider.provider)}
                      <div>
                        <p className="font-medium text-theme-primary capitalize">{provider.provider}</p>
                        <p className="text-xs text-theme-tertiary">{provider.model_count} models</p>
                      </div>
                    </div>
                  </td>
                  <td className="py-4 px-2 text-right">
                    <p className="font-semibold text-theme-primary">${provider.cost.toFixed(2)}</p>
                    <p className="text-xs text-theme-tertiary">
                      {((provider.cost / metrics.total_cost) * 100).toFixed(1)}% of total
                    </p>
                  </td>
                  <td className="py-4 px-2 text-right">
                    <p className="text-theme-primary">${provider.cost_per_1k_tokens.toFixed(4)}</p>
                    {provider.provider === cheapestProvider.provider && (
                      <Badge variant="success" size="sm" className="mt-1">Lowest</Badge>
                    )}
                  </td>
                  <td className="py-4 px-2 text-right">
                    <p className="text-theme-primary">{provider.execution_count.toLocaleString()}</p>
                  </td>
                  <td className="py-4 px-2 text-right">
                    <p className="text-theme-primary">${provider.avg_cost_per_execution.toFixed(4)}</p>
                  </td>
                  <td className="py-4 px-2 text-center">
                    <div className="flex flex-col items-center gap-1">
                      <span className="text-theme-primary font-medium">{provider.reliability_score}%</span>
                      {getScoreBadge(provider.reliability_score)}
                    </div>
                  </td>
                  <td className="py-4 px-2 text-center">
                    <div className="flex flex-col items-center gap-1">
                      <span className="text-theme-primary font-medium">{provider.performance_score}%</span>
                      {getScoreBadge(provider.performance_score)}
                    </div>
                  </td>
                  <td className="py-4 px-2 text-center">
                    {getTrendIcon(provider.cost_trend)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      {/* Cost Efficiency Matrix */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Cost-Performance Matrix</h3>
        <p className="text-sm text-theme-secondary mb-4">
          Efficiency Score = (Reliability × Performance) / Cost
        </p>
        <div className="space-y-3">
          {providerComparisons.map((provider) => {
            const efficiency = parseFloat(calculateEfficiency(provider));
            const maxEfficiency = parseFloat(calculateEfficiency(mostEfficientProvider));
            const percentage = (efficiency / maxEfficiency) * 100;

            return (
              <div key={provider.provider}>
                <div className="flex items-center justify-between mb-2">
                  <span className="text-theme-primary font-medium capitalize">{provider.provider}</span>
                  <span className="text-theme-primary font-semibold">{efficiency}</span>
                </div>
                <div className="w-full bg-theme-surface rounded-full h-2 mb-1">
                  <div
                    className={`h-2 rounded-full transition-all duration-300 ${
                      provider.provider === mostEfficientProvider.provider
                        ? 'bg-theme-success'
                        : 'bg-theme-interactive-primary'
                    }`}
                    style={{ width: `${percentage}%` }}
                  />
                </div>
                <div className="flex items-center justify-between text-xs text-theme-tertiary">
                  <span>R: {provider.reliability_score}% | P: {provider.performance_score}% | C: ${provider.cost.toFixed(2)}</span>
                  {provider.provider === mostEfficientProvider.provider && (
                    <Badge variant="success" size="sm">Best Value</Badge>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </Card>

      {/* Recommendations */}
      <Card className="p-6 bg-theme-info bg-opacity-5 border-theme-info">
        <div className="flex items-start gap-3">
          <AlertCircle className="h-5 w-5 text-theme-info flex-shrink-0 mt-0.5" />
          <div>
            <h4 className="font-semibold text-theme-primary mb-2">Optimization Recommendations</h4>
            <ul className="space-y-2 text-sm text-theme-secondary">
              <li className="flex items-start gap-2">
                <span className="text-theme-info mt-0.5">•</span>
                <span>
                  Consider using <span className="font-medium text-theme-primary capitalize">{cheapestProvider.provider}</span> for
                  cost-sensitive workloads (${cheapestProvider.cost_per_1k_tokens.toFixed(4)}/1K tokens)
                </span>
              </li>
              <li className="flex items-start gap-2">
                <span className="text-theme-info mt-0.5">•</span>
                <span>
                  Use <span className="font-medium text-theme-primary capitalize">{mostReliableProvider.provider}</span> for
                  mission-critical applications ({mostReliableProvider.reliability_score}% reliability)
                </span>
              </li>
              <li className="flex items-start gap-2">
                <span className="text-theme-info mt-0.5">•</span>
                <span>
                  <span className="font-medium text-theme-primary capitalize">{mostEfficientProvider.provider}</span> offers
                  the best cost-performance ratio for balanced workloads
                </span>
              </li>
            </ul>
          </div>
        </div>
      </Card>
    </div>
  );
};
