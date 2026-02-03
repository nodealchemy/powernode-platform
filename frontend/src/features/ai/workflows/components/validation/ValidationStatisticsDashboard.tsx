import React, { useState, useEffect } from 'react';
import { BarChart3, TrendingUp, TrendingDown, AlertCircle, CheckCircle, XCircle } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { validationApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface ValidationStatistics {
  overview: {
    total_workflows: number;
    validated_workflows: number;
    unvalidated_workflows: number;
    average_health_score: number;
    valid_count: number;
    invalid_count: number;
    warning_count: number;
    total_validations: number;
    validations_last_24h: number;
  };
  health_distribution: {
    healthy: number;
    unhealthy: number;
    moderate: number;
  };
  status_distribution: {
    valid: number;
    invalid: number;
    warning: number;
  };
  issue_categories: Record<string, number>;
  trends: Array<{
    date: string;
    avg_health_score: number;
    validation_count: number;
  }>;
  top_issues: Array<{
    code: string;
    severity: string;
    category: string;
    message: string;
    count: number;
  }>;
}

interface ValidationStatisticsDashboardProps {
  accountId?: string;
}

export const ValidationStatisticsDashboard: React.FC<ValidationStatisticsDashboardProps> = ({
  accountId: _accountId
}) => {
  const [statistics, setStatistics] = useState<ValidationStatistics | null>(null);
  const [timeRange, setTimeRange] = useState<'7d' | '30d' | '90d'>('30d');
  const [loading, setLoading] = useState(true);
  const { addNotification } = useNotifications();

   
  useEffect(() => {
    loadStatistics();
  }, [timeRange]);

  const loadStatistics = async () => {
    try {
      setLoading(true);
      const response = await validationApi.getValidationStatistics('', timeRange);
      setStatistics(response.statistics as unknown as ValidationStatistics);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Failed to Load Statistics',
        message: 'Could not load validation statistics'
      });
    } finally {
      setLoading(false);
    }
  };

  const getHealthScoreColor = (score: number) => {
    if (score >= 90) return 'text-theme-success';
    if (score >= 70) return 'text-theme-info';
    if (score >= 50) return 'text-theme-warning';
    return 'text-theme-error';
  };

  const getHealthScoreBg = (score: number) => {
    if (score >= 90) return 'bg-theme-success bg-opacity-10';
    if (score >= 70) return 'bg-theme-info bg-opacity-10';
    if (score >= 50) return 'bg-theme-warning bg-opacity-10';
    return 'bg-theme-error bg-opacity-10';
  };

  if (loading) {
    return (
      <div className="text-center py-12">
        <div className="animate-spin h-8 w-8 border-4 border-theme-interactive-primary border-t-transparent rounded-full mx-auto mb-4" />
        <p className="text-theme-secondary">Loading statistics...</p>
      </div>
    );
  }

  if (!statistics) {
    return (
      <Card className="p-8 text-center">
        <AlertCircle className="h-12 w-12 text-theme-tertiary mx-auto mb-4 opacity-50" />
        <p className="text-theme-secondary">No statistics available</p>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-theme-primary">Validation Statistics</h2>
          <p className="text-theme-secondary mt-1">
            Platform-wide workflow health metrics
          </p>
        </div>
        <Select
          value={timeRange}
          onChange={(value) => setTimeRange(value as '7d' | '30d' | '90d')}
          className="w-40"
        >
          <option value="7d">Last 7 Days</option>
          <option value="30d">Last 30 Days</option>
          <option value="90d">Last 90 Days</option>
        </Select>
      </div>

      {/* Overview Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card className="p-6">
          <div className="flex items-center justify-between mb-2">
            <p className="text-sm text-theme-tertiary">Total Workflows</p>
            <BarChart3 className="h-5 w-5 text-theme-tertiary" />
          </div>
          <p className="text-3xl font-bold text-theme-primary">
            {statistics.overview.total_workflows}
          </p>
          <p className="text-xs text-theme-secondary mt-1">
            {statistics.overview.validated_workflows} validated
          </p>
        </Card>

        <Card className={`p-6 ${getHealthScoreBg(statistics.overview.average_health_score)}`}>
          <div className="flex items-center justify-between mb-2">
            <p className="text-sm text-theme-tertiary">Average Health</p>
            {statistics.overview.average_health_score >= 80 ? (
              <TrendingUp className="h-5 w-5 text-theme-success" />
            ) : (
              <TrendingDown className="h-5 w-5 text-theme-error" />
            )}
          </div>
          <p className={`text-3xl font-bold ${getHealthScoreColor(statistics.overview.average_health_score)}`}>
            {statistics.overview.average_health_score}
          </p>
          <p className="text-xs text-theme-secondary mt-1">
            Health score
          </p>
        </Card>

        <Card className="p-6">
          <div className="flex items-center justify-between mb-2">
            <p className="text-sm text-theme-tertiary">Valid Workflows</p>
            <CheckCircle className="h-5 w-5 text-theme-success" />
          </div>
          <p className="text-3xl font-bold text-theme-success">
            {statistics.overview.valid_count}
          </p>
          <p className="text-xs text-theme-secondary mt-1">
            {((statistics.overview.valid_count / statistics.overview.validated_workflows) * 100).toFixed(1)}% of total
          </p>
        </Card>

        <Card className="p-6">
          <div className="flex items-center justify-between mb-2">
            <p className="text-sm text-theme-tertiary">Invalid Workflows</p>
            <XCircle className="h-5 w-5 text-theme-error" />
          </div>
          <p className="text-3xl font-bold text-theme-error">
            {statistics.overview.invalid_count}
          </p>
          <p className="text-xs text-theme-secondary mt-1">
            Require attention
          </p>
        </Card>
      </div>

      {/* Health Distribution */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Health Distribution</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-theme-success bg-opacity-10 rounded-lg p-4">
            <p className="text-sm text-theme-tertiary mb-1">Healthy (80+)</p>
            <p className="text-2xl font-bold text-theme-success">
              {statistics.health_distribution.healthy}
            </p>
          </div>
          <div className="bg-theme-warning bg-opacity-10 rounded-lg p-4">
            <p className="text-sm text-theme-tertiary mb-1">Moderate (60-79)</p>
            <p className="text-2xl font-bold text-theme-warning">
              {statistics.health_distribution.moderate}
            </p>
          </div>
          <div className="bg-theme-error bg-opacity-10 rounded-lg p-4">
            <p className="text-sm text-theme-tertiary mb-1">Unhealthy (&lt;60)</p>
            <p className="text-2xl font-bold text-theme-error">
              {statistics.health_distribution.unhealthy}
            </p>
          </div>
        </div>
      </Card>

      {/* Issue Categories */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Issue Categories</h3>
        <div className="space-y-3">
          {Object.entries(statistics.issue_categories).map(([category, count]) => (
            <div key={category} className="flex items-center justify-between">
              <div className="flex items-center gap-3 flex-1">
                <div className="w-32">
                  <p className="text-sm font-medium text-theme-primary capitalize">
                    {category.replace('_', ' ')}
                  </p>
                </div>
                <div className="flex-1 bg-theme-surface-secondary rounded-full h-2">
                  <div
                    className="bg-theme-interactive-primary h-2 rounded-full"
                    style={{
                      width: `${(count / Math.max(...Object.values(statistics.issue_categories))) * 100}%`
                    }}
                  />
                </div>
              </div>
              <p className="text-sm font-semibold text-theme-primary w-12 text-right">
                {count}
              </p>
            </div>
          ))}
        </div>
      </Card>

      {/* Top Issues */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Most Common Issues</h3>
        <div className="space-y-3">
          {statistics.top_issues.map((issue, index) => (
            <div
              key={issue.code}
              className="flex items-start gap-4 p-3 bg-theme-surface-secondary rounded-lg"
            >
              <div className="flex-shrink-0 w-8 h-8 bg-theme-surface rounded-full flex items-center justify-center text-sm font-semibold text-theme-primary">
                {index + 1}
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-2 mb-1">
                  <p className="font-medium text-theme-primary">{issue.code}</p>
                  <Badge variant={issue.severity === 'error' ? 'danger' : issue.severity === 'warning' ? 'warning' : 'secondary'}>
                    {issue.severity}
                  </Badge>
                  <Badge variant="outline">{issue.category}</Badge>
                </div>
                <p className="text-sm text-theme-secondary">{issue.message}</p>
              </div>
              <div className="flex-shrink-0 text-right">
                <p className="text-lg font-bold text-theme-primary">{issue.count}</p>
                <p className="text-xs text-theme-tertiary">occurrences</p>
              </div>
            </div>
          ))}
        </div>
      </Card>

      {/* Recent Activity */}
      <Card className="p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-theme-primary">Recent Activity</h3>
          <Badge variant="secondary">
            {statistics.overview.validations_last_24h} validations in 24h
          </Badge>
        </div>
        <p className="text-sm text-theme-secondary">
          Total validations: {statistics.overview.total_validations}
        </p>
      </Card>
    </div>
  );
};
