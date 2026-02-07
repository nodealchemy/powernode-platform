import React, { useState, useEffect } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import predictiveAnalyticsApi from '../services/predictiveAnalyticsApi';
import { ChurnRiskList } from '../components/ChurnRiskList';
import type { ChurnPrediction, PredictiveAnalyticsSummary } from '../types/predictive';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

export const ChurnRiskPage: React.FC = () => {
  const { showNotification } = useNotifications();
  const [predictions, setPredictions] = useState<ChurnPrediction[]>([]);
  const [summary, setSummary] = useState<PredictiveAnalyticsSummary | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [filter, setFilter] = useState<string>('all');
  const [selectedPrediction, setSelectedPrediction] = useState<ChurnPrediction | null>(null);
  const [isDetailModalOpen, setIsDetailModalOpen] = useState(false);

  const fetchData = async () => {
    setIsLoading(true);
    try {
      const params = filter === 'high_risk' ? { high_risk: true } : { risk_tier: filter !== 'all' ? filter : undefined };
      const [predictionsResponse, summaryResponse] = await Promise.all([
        predictiveAnalyticsApi.getChurnPredictions(params),
        predictiveAnalyticsApi.getSummary(),
      ]);
      setPredictions(predictionsResponse.data);
      setSummary(summaryResponse.data);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to load predictions';
      showNotification(message, 'error');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [filter]);

  const handleRunPredictions = async () => {
    try {
      await predictiveAnalyticsApi.predictChurn();
      showNotification('Churn predictions updated', 'success');
      fetchData();
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to run predictions';
      showNotification(message, 'error');
    }
  };

  const handleViewDetails = (prediction: ChurnPrediction) => {
    setSelectedPrediction(prediction);
    setIsDetailModalOpen(true);
  };

  const handleIntervene = (prediction: ChurnPrediction) => {
    showNotification(`Intervention workflow started for account ${prediction.account_id.substring(0, 8)}`, 'info');
  };

  const getRiskDistribution = () => {
    const distribution: Record<string, number> = {
      critical: 0,
      high: 0,
      medium: 0,
      low: 0,
      minimal: 0,
    };
    predictions.forEach((pred) => {
      distribution[pred.risk_tier] = (distribution[pred.risk_tier] || 0) + 1;
    });
    return distribution;
  };

  const distribution = getRiskDistribution();

  if (isLoading) {
    return (
      <PageContainer title="Churn Risk">
        <LoadingSpinner className="h-64" />
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Churn Risk Analysis"
      actions={[
        {
          label: 'Run Predictions',
          onClick: handleRunPredictions,
          variant: 'primary',
        },
      ]}
    >
      {/* Summary Cards */}
      {summary && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border border-l-4 border-l-theme-error">
            <p className="text-sm font-medium text-theme-text-secondary">High Risk</p>
            <p className="mt-2 text-3xl font-bold text-theme-error">
              {summary.churn_predictions.high_risk_count}
            </p>
            <p className="mt-1 text-sm text-theme-text-secondary">customers</p>
          </div>
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <p className="text-sm font-medium text-theme-text-secondary">Needs Intervention</p>
            <p className="mt-2 text-3xl font-bold text-theme-warning">
              {summary.churn_predictions.needs_intervention}
            </p>
            <p className="mt-1 text-sm text-theme-text-secondary">pending action</p>
          </div>
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <p className="text-sm font-medium text-theme-text-secondary">Avg Churn Probability</p>
            <p className="mt-2 text-3xl font-bold text-theme-text-primary">
              {((summary.churn_predictions.average_probability || 0) * 100).toFixed(1)}%
            </p>
          </div>
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <p className="text-sm font-medium text-theme-text-secondary">Total Analyzed</p>
            <p className="mt-2 text-3xl font-bold text-theme-text-primary">
              {predictions.length}
            </p>
            <p className="mt-1 text-sm text-theme-text-secondary">accounts</p>
          </div>
        </div>
      )}

      {/* Risk Tier Distribution */}
      <div className="bg-theme-bg-primary rounded-lg p-4 border border-theme-border mb-6">
        <p className="text-sm font-medium text-theme-text-secondary mb-3">Risk Distribution</p>
        <div className="flex gap-4">
          {Object.entries(distribution).map(([tier, count]) => (
            <div
              key={tier}
              className={`flex-1 text-center p-3 rounded-lg ${
                tier === 'critical' ? 'bg-theme-error-background' :
                tier === 'high' ? 'bg-theme-error-background' :
                tier === 'medium' ? 'bg-theme-warning-background' :
                tier === 'low' ? 'bg-theme-success-background' : 'bg-theme-success-background'
              }`}
            >
              <p className={`text-2xl font-bold ${
                tier === 'critical' ? 'text-theme-error' :
                tier === 'high' ? 'text-theme-error' :
                tier === 'medium' ? 'text-theme-warning' :
                tier === 'low' ? 'text-theme-success' : 'text-theme-success'
              }`}>
                {count}
              </p>
              <p className="text-xs text-theme-text-secondary capitalize">{tier}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Filters */}
      <div className="flex gap-2 mb-6">
        {['all', 'high_risk', 'critical', 'high', 'medium', 'low', 'minimal'].map((tier) => (
          <button
            key={tier}
            onClick={() => setFilter(tier)}
            className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
              filter === tier
                ? 'bg-theme-primary text-white'
                : 'bg-theme-bg-secondary text-theme-text-secondary hover:bg-theme-bg-tertiary'
            }`}
          >
            {tier === 'all' ? 'All' : tier === 'high_risk' ? 'High Risk' : tier.charAt(0).toUpperCase() + tier.slice(1)}
          </button>
        ))}
      </div>

      {/* Predictions List */}
      <ChurnRiskList
        predictions={predictions}
        onSelect={handleViewDetails}
        onIntervene={handleIntervene}
      />

      {/* Detail Modal */}
      <Modal
        isOpen={isDetailModalOpen}
        onClose={() => setIsDetailModalOpen(false)}
        title="Churn Prediction Details"
      >
        {selectedPrediction && (
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-theme-text-secondary">Churn Probability</p>
                <p className="text-2xl font-bold text-theme-text-primary">
                  {selectedPrediction.probability_percentage}%
                </p>
              </div>
              <div>
                <p className="text-sm text-theme-text-secondary">Risk Tier</p>
                <p className="text-2xl font-bold text-theme-text-primary capitalize">
                  {selectedPrediction.risk_tier}
                </p>
              </div>
              <div>
                <p className="text-sm text-theme-text-secondary">Predicted Churn Date</p>
                <p className="font-medium text-theme-text-primary">
                  {selectedPrediction.predicted_churn_date || 'N/A'}
                </p>
              </div>
              <div>
                <p className="text-sm text-theme-text-secondary">Confidence</p>
                <p className="font-medium text-theme-text-primary">
                  {((selectedPrediction.confidence_score || 0) * 100).toFixed(0)}%
                </p>
              </div>
            </div>

            {selectedPrediction.contributing_factors && selectedPrediction.contributing_factors.length > 0 && (
              <div>
                <p className="text-sm font-medium text-theme-text-secondary mb-2">Contributing Factors</p>
                <div className="space-y-2">
                  {selectedPrediction.contributing_factors.map((factor, index) => (
                    <div key={index} className="flex items-center justify-between p-3 bg-theme-bg-secondary rounded-lg">
                      <div>
                        <p className="font-medium text-theme-text-primary">{factor.description}</p>
                        <p className="text-sm text-theme-text-secondary capitalize">{factor.factor.replace('_', ' ')}</p>
                      </div>
                      <span className="px-2 py-1 bg-theme-bg-tertiary rounded text-sm">
                        Weight: {(factor.weight * 100).toFixed(0)}%
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {selectedPrediction.recommended_actions.length > 0 && (
              <div>
                <p className="text-sm font-medium text-theme-text-secondary mb-2">Recommended Actions</p>
                <div className="space-y-2">
                  {selectedPrediction.recommended_actions.map((action, index) => (
                    <div key={index} className={`p-3 rounded-lg ${
                      action.priority === 'high' ? 'bg-theme-error-background' :
                      action.priority === 'medium' ? 'bg-theme-warning-background' : 'bg-theme-bg-secondary'
                    }`}>
                      <div className="flex items-center justify-between">
                        <p className="font-medium text-theme-text-primary">{action.description}</p>
                        <span className={`px-2 py-0.5 rounded text-xs font-medium ${
                          action.priority === 'high' ? 'bg-theme-error-background text-theme-error' :
                          action.priority === 'medium' ? 'bg-theme-warning-background text-theme-warning' : 'bg-theme-bg-tertiary text-theme-text-secondary'
                        }`}>
                          {action.priority}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            <div className="flex justify-end gap-3 pt-4">
              <Button variant="secondary" onClick={() => setIsDetailModalOpen(false)}>
                Close
              </Button>
              <Button variant="primary" onClick={() => handleIntervene(selectedPrediction)}>
                Start Intervention
              </Button>
            </div>
          </div>
        )}
      </Modal>
    </PageContainer>
  );
};

export default ChurnRiskPage;
