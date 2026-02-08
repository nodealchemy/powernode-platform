import React, { useState, useCallback, useEffect } from 'react';
import { Lightbulb, CheckCircle, TrendingUp, ArrowRight } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { apiClient } from '@/shared/services/apiClient';

interface Recommendation {
  id: string;
  recommendation_type: string;
  target_type: string;
  target_id: string;
  current_config: Record<string, unknown>;
  recommended_config: Record<string, unknown>;
  evidence: Record<string, unknown>;
  confidence_score: number;
  status: string;
  created_at: string;
}

const TYPE_LABELS: Record<string, string> = {
  provider_switch: 'Provider Switch',
  team_composition: 'Team Composition',
  timeout_adjustment: 'Timeout Adjustment',
  model_upgrade: 'Model Upgrade',
  cost_optimization: 'Cost Optimization',
};

export const RecommendationsDashboard: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const { addNotification } = useNotifications();

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const response = await apiClient.get('/api/v1/ai/learning/recommendations');
      setRecommendations(response.data?.recommendations || []);
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to load recommendations' });
    } finally {
      setLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const applyRecommendation = async (id: string) => {
    try {
      await apiClient.post(`/api/v1/ai/learning/recommendations/${id}/apply`);
      addNotification({ type: 'success', message: 'Recommendation applied' });
      loadData();
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to apply recommendation' });
    }
  };

  const dismissRecommendation = async (id: string) => {
    try {
      await apiClient.post(`/api/v1/ai/learning/recommendations/${id}/dismiss`);
      loadData();
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to dismiss recommendation' });
    }
  };

  if (loading) return <LoadingSpinner />;

  const pending = recommendations.filter((r) => r.status === 'pending');
  const applied = recommendations.filter((r) => r.status === 'applied');

  return (
    <PageContainer
      title="Improvement Recommendations"
      description="AI-generated recommendations based on trajectory analysis"
    >
      <div className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Card>
            <CardContent className="p-4 flex items-center gap-3">
              <Lightbulb className="w-8 h-8 text-theme-warning" />
              <div>
                <p className="text-sm text-theme-muted">Pending</p>
                <p className="text-2xl font-bold text-theme-primary">{pending.length}</p>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4 flex items-center gap-3">
              <CheckCircle className="w-8 h-8 text-theme-success" />
              <div>
                <p className="text-sm text-theme-muted">Applied</p>
                <p className="text-2xl font-bold text-theme-primary">{applied.length}</p>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-4 flex items-center gap-3">
              <TrendingUp className="w-8 h-8 text-theme-info" />
              <div>
                <p className="text-sm text-theme-muted">Total</p>
                <p className="text-2xl font-bold text-theme-primary">{recommendations.length}</p>
              </div>
            </CardContent>
          </Card>
        </div>

        {pending.length > 0 && (
          <Card>
            <CardHeader title="Pending Recommendations" />
            <CardContent>
              <div className="space-y-3">
                {pending.map((rec) => (
                  <div
                    key={rec.id}
                    className="p-4 rounded-lg bg-theme-surface border border-theme-border"
                  >
                    <div className="flex items-start justify-between">
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          <span className="text-sm font-medium text-theme-primary">
                            {TYPE_LABELS[rec.recommendation_type] || rec.recommendation_type}
                          </span>
                          <Badge variant="default">
                            {Math.round(rec.confidence_score * 100)}% confidence
                          </Badge>
                        </div>
                        <p className="text-sm text-theme-secondary">
                          {(rec.evidence as Record<string, string>)?.suggestion ||
                            (rec.evidence as Record<string, string>)?.improvement ||
                            'Review this recommendation'}
                        </p>
                        {(rec.evidence as Record<string, string>)?.current_provider && (
                          <div className="flex items-center gap-2 mt-2 text-xs text-theme-muted">
                            <span>{(rec.evidence as Record<string, string>).current_provider}</span>
                            <ArrowRight className="w-3 h-3" />
                            <span>{(rec.evidence as Record<string, string>).recommended_provider}</span>
                          </div>
                        )}
                      </div>
                      <div className="flex items-center gap-2 ml-4">
                        <button
                          onClick={() => applyRecommendation(rec.id)}
                          className="px-3 py-1.5 text-xs font-medium bg-theme-primary text-white rounded-md hover:opacity-90"
                        >
                          Apply
                        </button>
                        <button
                          onClick={() => dismissRecommendation(rec.id)}
                          className="px-3 py-1.5 text-xs font-medium bg-theme-surface border border-theme-border rounded-md hover:bg-theme-surface-hover"
                        >
                          Dismiss
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}

        {pending.length === 0 && (
          <Card>
            <CardContent className="p-8 text-center text-theme-muted">
              <Lightbulb className="w-12 h-12 mx-auto mb-3 opacity-30" />
              <p>No pending recommendations. The system will generate new ones during the next analysis cycle.</p>
            </CardContent>
          </Card>
        )}
      </div>
    </PageContainer>
  );
};
