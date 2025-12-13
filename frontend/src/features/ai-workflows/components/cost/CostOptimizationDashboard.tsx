import React, { useState, useEffect, useCallback } from 'react';
import {
  DollarSign,
  TrendingDown,
  TrendingUp,
  AlertTriangle,
  RefreshCw,
  Download,
  Calendar,
  Loader2,
  Zap,
  Target,
  BarChart3
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { useNotifications } from '@/shared/hooks/useNotifications';

export interface CostMetrics {
  total_cost: number;
  cost_by_provider: Record<string, number>;
  cost_by_model: Record<string, number>;
  cost_by_workflow: Record<string, { cost: number; executions: number }>;
  total_tokens: number;
  tokens_by_provider: Record<string, number>;
  period_start: string;
  period_end: string;
  daily_costs: Record<string, number>;
  cost_trends: {
    daily_average: number;
    weekly_average: number;
    monthly_average: number;
    trend_direction: 'up' | 'down' | 'stable';
    trend_percentage: number;
  };
}

export interface CostBudget {
  daily_limit?: number;
  weekly_limit?: number;
  monthly_limit?: number;
  alerts_enabled: boolean;
  alert_threshold_percentage: number;
}

export interface CostOptimizationSuggestion {
  id: string;
  type: 'model_switch' | 'batch_optimization' | 'caching' | 'rate_limiting' | 'scheduling';
  title: string;
  description: string;
  estimated_savings: number;
  estimated_savings_percentage: number;
  impact: 'high' | 'medium' | 'low';
  effort: 'easy' | 'moderate' | 'complex';
  actionable: boolean;
  action_url?: string;
}

interface CostOptimizationDashboardProps {
  metrics?: CostMetrics | null;
  budget?: CostBudget | null;
  suggestions?: CostOptimizationSuggestion[];
  loading?: boolean;
  onLoadMetrics?: (timeRange: string) => Promise<CostMetrics>;
  onLoadBudget?: () => Promise<CostBudget>;
  onLoadSuggestions?: () => Promise<CostOptimizationSuggestion[]>;
}

export const CostOptimizationDashboard: React.FC<CostOptimizationDashboardProps> = ({
  metrics: propMetrics,
  budget: propBudget,
  suggestions: propSuggestions,
  loading: propLoading,
  onLoadMetrics,
  onLoadBudget,
  onLoadSuggestions
}) => {
  const [timeRange, setTimeRange] = useState<'24h' | '7d' | '30d' | '90d'>('30d');
  const [metrics, setMetrics] = useState<CostMetrics | null>(propMetrics || null);
  const [budget, setBudget] = useState<CostBudget | null>(propBudget || null);
  const [suggestions, setSuggestions] = useState<CostOptimizationSuggestion[]>(propSuggestions || []);
  const [loading, setLoading] = useState(!propMetrics && !propLoading);
  const [refreshing, setRefreshing] = useState(false);

  const { addNotification } = useNotifications();

  // Sync props to state when they change
  useEffect(() => {
    if (propMetrics !== undefined) setMetrics(propMetrics);
  }, [propMetrics]);

  useEffect(() => {
    if (propBudget !== undefined) setBudget(propBudget);
  }, [propBudget]);

  useEffect(() => {
    if (propSuggestions !== undefined) setSuggestions(propSuggestions);
  }, [propSuggestions]);

  const loadData = useCallback(async (showSpinner = true) => {
    // Skip loading if all data is provided via props
    if (propMetrics && propBudget && propSuggestions) return;

    try {
      if (showSpinner) setLoading(true);
      else setRefreshing(true);

      const promises: Promise<unknown>[] = [];

      if (!propMetrics && onLoadMetrics) {
        promises.push(onLoadMetrics(timeRange).then(setMetrics));
      }
      if (!propBudget && onLoadBudget) {
        promises.push(onLoadBudget().then(setBudget));
      }
      if (!propSuggestions && onLoadSuggestions) {
        promises.push(onLoadSuggestions().then(setSuggestions));
      }

      await Promise.all(promises);
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to load cost data:', error);
      }
      addNotification({
        type: 'error',
        title: 'Load Error',
        message: 'Failed to load cost optimization data'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [timeRange, propMetrics, propBudget, propSuggestions, onLoadMetrics, onLoadBudget, onLoadSuggestions, addNotification]);

  useEffect(() => {
    // Only load data if not provided via props and callbacks exist
    if ((!propMetrics && onLoadMetrics) || (!propBudget && onLoadBudget) || (!propSuggestions && onLoadSuggestions)) {
      loadData();
    } else if (!propMetrics && !onLoadMetrics) {
      // No data and no way to load it - stop loading
      setLoading(false);
    }
  }, [loadData, propMetrics, propBudget, propSuggestions, onLoadMetrics, onLoadBudget, onLoadSuggestions]);

  const handleExport = () => {
    if (!metrics) return;

    const data = {
      exported_at: new Date().toISOString(),
      time_range: timeRange,
      metrics,
      budget,
      suggestions
    };

    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `cost-optimization-${timeRange}-${new Date().toISOString()}.json`;
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);

    addNotification({
      type: 'success',
      title: 'Exported',
      message: 'Cost data exported successfully'
    });
  };

  const getTrendIcon = () => {
    if (!metrics?.cost_trends) return null;

    const { trend_direction } = metrics.cost_trends;
    if (trend_direction === 'up') {
      return <TrendingUp className="h-4 w-4 text-theme-error" />;
    } else if (trend_direction === 'down') {
      return <TrendingDown className="h-4 w-4 text-theme-success" />;
    }
    return null;
  };

  const getBudgetStatus = () => {
    if (!metrics || !budget) return null;

    const dailyCost = metrics.cost_trends.daily_average;
    const weeklyCost = metrics.cost_trends.weekly_average;
    const monthlyCost = metrics.cost_trends.monthly_average;

    const alerts: Array<{ level: 'warning' | 'error'; message: string }> = [];

    if (budget.daily_limit && dailyCost > budget.daily_limit) {
      alerts.push({
        level: 'error',
        message: `Daily cost ($${dailyCost.toFixed(2)}) exceeds limit ($${budget.daily_limit.toFixed(2)})`
      });
    }

    if (budget.weekly_limit && weeklyCost > budget.weekly_limit) {
      alerts.push({
        level: 'error',
        message: `Weekly cost ($${weeklyCost.toFixed(2)}) exceeds limit ($${budget.weekly_limit.toFixed(2)})`
      });
    }

    if (budget.monthly_limit && monthlyCost > budget.monthly_limit) {
      alerts.push({
        level: 'error',
        message: `Monthly cost ($${monthlyCost.toFixed(2)}) exceeds limit ($${budget.monthly_limit.toFixed(2)})`
      });
    }

    // Check alert threshold
    if (budget.alerts_enabled && budget.daily_limit) {
      const thresholdCost = budget.daily_limit * (budget.alert_threshold_percentage / 100);
      if (dailyCost > thresholdCost && dailyCost <= budget.daily_limit) {
        alerts.push({
          level: 'warning',
          message: `Daily cost is ${budget.alert_threshold_percentage}% of limit`
        });
      }
    }

    return alerts;
  };

  const getSuggestionImpactColor = (impact: CostOptimizationSuggestion['impact']) => {
    switch (impact) {
      case 'high':
        return 'text-theme-success';
      case 'medium':
        return 'text-theme-warning';
      case 'low':
        return 'text-theme-tertiary';
    }
  };

  const getEffortBadge = (effort: CostOptimizationSuggestion['effort']) => {
    switch (effort) {
      case 'easy':
        return <Badge variant="success" size="sm">Easy</Badge>;
      case 'moderate':
        return <Badge variant="warning" size="sm">Moderate</Badge>;
      case 'complex':
        return <Badge variant="outline" size="sm">Complex</Badge>;
    }
  };

  const isLoading = propLoading !== undefined ? propLoading : loading;

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-8 w-8 animate-spin text-theme-interactive-primary" />
      </div>
    );
  }

  if (!metrics) {
    return (
      <div className="text-center py-12 text-theme-tertiary">
        <p>No cost data available</p>
      </div>
    );
  }

  const budgetAlerts = getBudgetStatus();
  const totalEstimatedSavings = suggestions.reduce((sum, s) => sum + s.estimated_savings, 0);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-theme-primary">Cost Optimization</h2>
          <p className="text-theme-tertiary mt-1">
            Analyze and optimize AI execution costs across providers and workflows
          </p>
        </div>

        <div className="flex items-center gap-2">
          <Select
            value={timeRange}
            onChange={(value) => setTimeRange(value as any)}
            className="w-32"
          >
            <option value="24h">Last 24h</option>
            <option value="7d">Last 7 days</option>
            <option value="30d">Last 30 days</option>
            <option value="90d">Last 90 days</option>
          </Select>

          <Button
            variant="outline"
            size="sm"
            onClick={() => loadData(false)}
            disabled={refreshing}
            className="flex items-center gap-1"
          >
            <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
            Refresh
          </Button>

          <Button
            variant="outline"
            size="sm"
            onClick={handleExport}
            className="flex items-center gap-1"
          >
            <Download className="h-4 w-4" />
            Export
          </Button>
        </div>
      </div>

      {/* Budget Alerts */}
      {budgetAlerts && budgetAlerts.length > 0 && (
        <div className="space-y-2">
          {budgetAlerts.map((alert, index) => (
            <div
              key={index}
              className={`p-4 rounded-lg border ${
                alert.level === 'error'
                  ? 'bg-theme-error bg-opacity-10 border-theme-error'
                  : 'bg-theme-warning bg-opacity-10 border-theme-warning'
              }`}
            >
              <div className="flex items-center gap-2">
                <AlertTriangle
                  className={`h-5 w-5 ${
                    alert.level === 'error' ? 'text-theme-error' : 'text-theme-warning'
                  }`}
                />
                <span className="text-theme-primary font-medium">{alert.message}</span>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Cost Overview Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card className="p-6">
          <div className="flex items-center justify-between mb-2">
            <span className="text-theme-tertiary text-sm">Total Cost</span>
            <DollarSign className="h-5 w-5 text-theme-primary" />
          </div>
          <div className="text-3xl font-bold text-theme-primary mb-1">
            ${metrics.total_cost.toFixed(2)}
          </div>
          <div className="flex items-center gap-1 text-sm">
            {getTrendIcon()}
            <span className={
              metrics.cost_trends.trend_direction === 'up'
                ? 'text-theme-error'
                : metrics.cost_trends.trend_direction === 'down'
                ? 'text-theme-success'
                : 'text-theme-tertiary'
            }>
              {metrics.cost_trends.trend_percentage.toFixed(1)}% vs last period
            </span>
          </div>
        </Card>

        <Card className="p-6">
          <div className="flex items-center justify-between mb-2">
            <span className="text-theme-tertiary text-sm">Daily Average</span>
            <Calendar className="h-5 w-5 text-theme-primary" />
          </div>
          <div className="text-3xl font-bold text-theme-primary mb-1">
            ${metrics.cost_trends.daily_average.toFixed(2)}
          </div>
          <div className="text-sm text-theme-tertiary">
            Per day in selected period
          </div>
        </Card>

        <Card className="p-6">
          <div className="flex items-center justify-between mb-2">
            <span className="text-theme-tertiary text-sm">Total Tokens</span>
            <Zap className="h-5 w-5 text-theme-primary" />
          </div>
          <div className="text-3xl font-bold text-theme-primary mb-1">
            {(metrics.total_tokens / 1000000).toFixed(2)}M
          </div>
          <div className="text-sm text-theme-tertiary">
            Tokens consumed
          </div>
        </Card>

        <Card className="p-6">
          <div className="flex items-center justify-between mb-2">
            <span className="text-theme-tertiary text-sm">Potential Savings</span>
            <Target className="h-5 w-5 text-theme-success" />
          </div>
          <div className="text-3xl font-bold text-theme-success mb-1">
            ${totalEstimatedSavings.toFixed(2)}
          </div>
          <div className="text-sm text-theme-tertiary">
            {suggestions.length} optimization{suggestions.length !== 1 ? 's' : ''} available
          </div>
        </Card>
      </div>

      {/* Cost by Provider */}
      <Card className="p-6">
        <div className="flex items-center gap-2 mb-4">
          <BarChart3 className="h-5 w-5 text-theme-primary" />
          <h3 className="text-lg font-semibold text-theme-primary">Cost by Provider</h3>
        </div>
        <div className="space-y-3">
          {Object.entries(metrics.cost_by_provider)
            .sort(([, a], [, b]) => b - a)
            .map(([provider, cost]) => {
              const percentage = (cost / metrics.total_cost) * 100;
              return (
                <div key={provider}>
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-theme-primary font-medium capitalize">{provider}</span>
                    <span className="text-theme-primary font-semibold">${cost.toFixed(2)}</span>
                  </div>
                  <div className="w-full bg-theme-surface rounded-full h-2">
                    <div
                      className="bg-theme-interactive-primary h-2 rounded-full transition-all duration-300"
                      style={{ width: `${percentage}%` }}
                    />
                  </div>
                  <span className="text-xs text-theme-tertiary">{percentage.toFixed(1)}% of total</span>
                </div>
              );
            })}
        </div>
      </Card>

      {/* Optimization Suggestions */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">
          Optimization Recommendations
        </h3>
        <div className="space-y-3">
          {suggestions.length === 0 ? (
            <div className="text-center py-8 text-theme-tertiary">
              <p>No optimization suggestions at this time</p>
              <p className="text-sm mt-1">Your costs are already well optimized!</p>
            </div>
          ) : (
            suggestions.map((suggestion) => (
              <div
                key={suggestion.id}
                className="p-4 border border-theme rounded-lg hover:bg-theme-surface transition-colors"
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <h4 className="font-medium text-theme-primary">{suggestion.title}</h4>
                      {getEffortBadge(suggestion.effort)}
                    </div>
                    <p className="text-sm text-theme-secondary mb-2">{suggestion.description}</p>
                    <div className="flex items-center gap-4 text-xs text-theme-tertiary">
                      <span>
                        Impact: <span className={`font-medium ${getSuggestionImpactColor(suggestion.impact)}`}>
                          {suggestion.impact.toUpperCase()}
                        </span>
                      </span>
                      <span>
                        Estimated Savings: <span className="font-medium text-theme-success">
                          ${suggestion.estimated_savings.toFixed(2)} ({suggestion.estimated_savings_percentage.toFixed(1)}%)
                        </span>
                      </span>
                    </div>
                  </div>
                  {suggestion.actionable && suggestion.action_url && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => window.location.href = suggestion.action_url!}
                      className="ml-4"
                    >
                      Apply
                    </Button>
                  )}
                </div>
              </div>
            ))
          )}
        </div>
      </Card>
    </div>
  );
};
