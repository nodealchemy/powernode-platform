import React, { useState, useEffect } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import predictiveAnalyticsApi from '../services/predictiveAnalyticsApi';
import { HealthScoreCard } from '../components/HealthScoreCard';
import type { CustomerHealthScore, PredictiveAnalyticsSummary } from '../types/predictive';

export const CustomerHealthPage: React.FC = () => {
  const { showNotification } = useNotifications();
  const [healthScores, setHealthScores] = useState<CustomerHealthScore[]>([]);
  const [summary, setSummary] = useState<PredictiveAnalyticsSummary | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [filter, setFilter] = useState<string>('all');

  const fetchData = async () => {
    setIsLoading(true);
    try {
      const [scoresResponse, summaryResponse] = await Promise.all([
        predictiveAnalyticsApi.getHealthScores({
          at_risk: filter === 'at_risk' ? true : undefined,
          status: filter !== 'all' && filter !== 'at_risk' ? filter : undefined,
        }),
        predictiveAnalyticsApi.getSummary(),
      ]);
      setHealthScores(scoresResponse.data);
      setSummary(summaryResponse.data);
    } catch {
      const message = error instanceof Error ? error.message : 'Failed to load health scores';
      showNotification(message, 'error');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [filter]);

  const handleRecalculate = async () => {
    try {
      await predictiveAnalyticsApi.calculateHealthScore();
      showNotification('Health scores recalculated', 'success');
      fetchData();
    } catch {
      const message = error instanceof Error ? error.message : 'Failed to recalculate';
      showNotification(message, 'error');
    }
  };

  const getStatusDistribution = () => {
    const distribution: Record<string, number> = {
      thriving: 0,
      healthy: 0,
      needs_attention: 0,
      at_risk: 0,
      critical: 0,
    };
    healthScores.forEach((score) => {
      distribution[score.health_status] = (distribution[score.health_status] || 0) + 1;
    });
    return distribution;
  };

  const distribution = getStatusDistribution();

  if (isLoading) {
    return (
      <PageContainer title="Customer Health">
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary" />
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Customer Health"
      actions={[
        {
          label: 'Recalculate Scores',
          onClick: handleRecalculate,
          variant: 'primary',
        },
      ]}
    >
      {/* Summary Cards */}
      {summary && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <p className="text-sm font-medium text-theme-text-secondary">At Risk</p>
            <p className="mt-2 text-3xl font-bold text-theme-error">
              {summary.health_scores.at_risk_count}
            </p>
          </div>
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <p className="text-sm font-medium text-theme-text-secondary">Healthy</p>
            <p className="mt-2 text-3xl font-bold text-theme-success">
              {summary.health_scores.healthy_count}
            </p>
          </div>
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <p className="text-sm font-medium text-theme-text-secondary">Average Score</p>
            <p className="mt-2 text-3xl font-bold text-theme-text-primary">
              {summary.health_scores.average_score?.toFixed(1) || '-'}
            </p>
          </div>
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <p className="text-sm font-medium text-theme-text-secondary">Needs Intervention</p>
            <p className="mt-2 text-3xl font-bold text-theme-warning">
              {summary.churn_predictions.needs_intervention}
            </p>
          </div>
        </div>
      )}

      {/* Distribution Bar */}
      <div className="bg-theme-bg-primary rounded-lg p-4 border border-theme-border mb-6">
        <p className="text-sm font-medium text-theme-text-secondary mb-3">Health Distribution</p>
        <div className="flex rounded-full overflow-hidden h-4">
          <div
            className="bg-theme-success"
            style={{ width: `${(distribution.thriving / healthScores.length) * 100}%` }}
            title={`Thriving: ${distribution.thriving}`}
          />
          <div
            className="bg-theme-success opacity-70"
            style={{ width: `${(distribution.healthy / healthScores.length) * 100}%` }}
            title={`Healthy: ${distribution.healthy}`}
          />
          <div
            className="bg-theme-warning"
            style={{ width: `${(distribution.needs_attention / healthScores.length) * 100}%` }}
            title={`Needs Attention: ${distribution.needs_attention}`}
          />
          <div
            className="bg-theme-warning opacity-70"
            style={{ width: `${(distribution.at_risk / healthScores.length) * 100}%` }}
            title={`At Risk: ${distribution.at_risk}`}
          />
          <div
            className="bg-theme-error"
            style={{ width: `${(distribution.critical / healthScores.length) * 100}%` }}
            title={`Critical: ${distribution.critical}`}
          />
        </div>
        <div className="flex justify-between mt-2 text-xs text-theme-text-secondary">
          <span className="flex items-center gap-1">
            <span className="w-3 h-3 rounded-full bg-theme-success" /> Thriving ({distribution.thriving})
          </span>
          <span className="flex items-center gap-1">
            <span className="w-3 h-3 rounded-full bg-theme-success opacity-70" /> Healthy ({distribution.healthy})
          </span>
          <span className="flex items-center gap-1">
            <span className="w-3 h-3 rounded-full bg-theme-warning" /> Attention ({distribution.needs_attention})
          </span>
          <span className="flex items-center gap-1">
            <span className="w-3 h-3 rounded-full bg-theme-warning opacity-70" /> At Risk ({distribution.at_risk})
          </span>
          <span className="flex items-center gap-1">
            <span className="w-3 h-3 rounded-full bg-theme-error" /> Critical ({distribution.critical})
          </span>
        </div>
      </div>

      {/* Filters */}
      <div className="flex gap-2 mb-6">
        {['all', 'at_risk', 'critical', 'needs_attention', 'healthy', 'thriving'].map((status) => (
          <button
            key={status}
            onClick={() => setFilter(status)}
            className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
              filter === status
                ? 'bg-theme-primary text-white'
                : 'bg-theme-bg-secondary text-theme-text-secondary hover:bg-theme-bg-tertiary'
            }`}
          >
            {status === 'all' ? 'All' : status.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())}
          </button>
        ))}
      </div>

      {/* Health Score Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {healthScores.map((score) => (
          <HealthScoreCard
            key={score.id}
            healthScore={score}
            showDetails
          />
        ))}
      </div>

      {healthScores.length === 0 && (
        <div className="text-center py-12 bg-theme-bg-primary rounded-lg border border-theme-border">
          <p className="text-theme-text-secondary">No health scores match your filter.</p>
        </div>
      )}
    </PageContainer>
  );
};

export default CustomerHealthPage;
