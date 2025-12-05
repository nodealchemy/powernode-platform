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
  onLoadMetrics?: (timeRange: string) => Promise<CostMetrics>;
  onLoadBudget?: () => Promise<CostBudget>;
  onLoadSuggestions?: () => Promise<CostOptimizationSuggestion[]>;
}

export const CostOptimizationDashboard: React.FC<CostOptimizationDashboardProps> = ({
  onLoadMetrics,
  onLoadBudget,
  onLoadSuggestions
}) => {
  const [timeRange, setTimeRange] = useState<'24h' | '7d' | '30d' | '90d'>('30d');
  const [metrics, setMetrics] = useState<CostMetrics | null>(null);
  const [budget, setBudget] = useState<CostBudget | null>(null);
  const [suggestions, setSuggestions] = useState<CostOptimizationSuggestion[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const { addNotification } = useNotifications();

  const loadData = useCallback(async (showSpinner = true) => {
    try {
      if (showSpinner) setLoading(true);
      else setRefreshing(true);

      const [metricsData, budgetData, suggestionsData] = await Promise.all([
        onLoadMetrics?.(timeRange) || Promise.resolve(generateMockMetrics()),
        onLoadBudget?.() || Promise.resolve(generateMockBudget()),
        onLoadSuggestions?.() || Promise.resolve(generateMockSuggestions())
      ]);

      setMetrics(metricsData);
      setBudget(budgetData);
      setSuggestions(suggestionsData);
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
  }, [timeRange, onLoadMetrics, onLoadBudget, onLoadSuggestions, addNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

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

  if (loading) {
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

// Mock data generators for development
function generateMockMetrics(): CostMetrics {
  return {
    total_cost: 127.45,
    cost_by_provider: {
      openai: 78.30,
      anthropic: 32.15,
      ollama: 17.00
    },
    cost_by_model: {
      'gpt-4': 52.30,
      'gpt-3.5-turbo': 26.00,
      'claude-3-opus': 25.15,
      'claude-3-sonnet': 7.00,
      'llama2': 17.00
    },
    cost_by_workflow: {
      'content-generation': { cost: 45.20, executions: 234 },
      'data-analysis': { cost: 38.50, executions: 156 },
      'code-review': { cost: 28.75, executions: 89 },
      'customer-support': { cost: 15.00, executions: 421 }
    },
    total_tokens: 42500000,
    tokens_by_provider: {
      openai: 26000000,
      anthropic: 10500000,
      ollama: 6000000
    },
    period_start: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(),
    period_end: new Date().toISOString(),
    daily_costs: {},
    cost_trends: {
      daily_average: 4.25,
      weekly_average: 29.75,
      monthly_average: 127.45,
      trend_direction: 'down',
      trend_percentage: 12.3
    }
  };
}

function generateMockBudget(): CostBudget {
  return {
    daily_limit: 10.00,
    weekly_limit: 50.00,
    monthly_limit: 200.00,
    alerts_enabled: true,
    alert_threshold_percentage: 80
  };
}

function generateMockSuggestions(): CostOptimizationSuggestion[] {
  return [
    {
      id: '1',
      type: 'model_switch',
      title: 'Switch to GPT-3.5-turbo for simple tasks',
      description: 'Many of your workflows could use GPT-3.5-turbo instead of GPT-4, reducing costs by 90% with minimal quality impact.',
      estimated_savings: 38.50,
      estimated_savings_percentage: 30.2,
      impact: 'high',
      effort: 'easy',
      actionable: true,
      action_url: '/app/ai/workflows'
    },
    {
      id: '2',
      type: 'batch_optimization',
      title: 'Enable batch processing for recurring tasks',
      description: 'Batch similar requests together to reduce overhead and improve cost efficiency.',
      estimated_savings: 15.20,
      estimated_savings_percentage: 11.9,
      impact: 'medium',
      effort: 'moderate',
      actionable: true,
      action_url: '/app/ai/workflows'
    },
    {
      id: '3',
      type: 'caching',
      title: 'Implement response caching',
      description: 'Cache responses for frequently asked questions to avoid redundant API calls.',
      estimated_savings: 22.80,
      estimated_savings_percentage: 17.9,
      impact: 'high',
      effort: 'moderate',
      actionable: false
    }
  ];
}
