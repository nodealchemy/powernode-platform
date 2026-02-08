import React, { useState, useCallback, useEffect } from 'react';
import { BarChart3, TrendingUp, TrendingDown, Minus } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { apiClient } from '@/shared/services/apiClient';

interface AgentScoreTrend {
  agent_id: string;
  agent_name: string;
  count: number;
  average_correctness: number | null;
  average_completeness: number | null;
  average_helpfulness: number | null;
  average_safety: number | null;
  trend: string;
}

interface CacheMetrics {
  hits: number;
  misses: number;
  hit_rate: number;
  estimated_savings_usd: number;
}

const TrendIcon: React.FC<{ trend: string }> = ({ trend }) => {
  switch (trend) {
    case 'improving':
      return <TrendingUp className="w-4 h-4 text-theme-success" />;
    case 'declining':
      return <TrendingDown className="w-4 h-4 text-theme-error" />;
    default:
      return <Minus className="w-4 h-4 text-theme-muted" />;
  }
};

export const TrajectoryInsights: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [agentTrends, setAgentTrends] = useState<AgentScoreTrend[]>([]);
  const [cacheMetrics, setCacheMetrics] = useState<CacheMetrics | null>(null);
  const { addNotification } = useNotifications();

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const [trendsRes, cacheRes] = await Promise.all([
        apiClient.get('/api/v1/ai/learning/agent_trends'),
        apiClient.get('/api/v1/ai/learning/cache_metrics'),
      ]);
      setAgentTrends(trendsRes.data?.trends || []);
      setCacheMetrics(cacheRes.data?.metrics || null);
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to load insights' });
    } finally {
      setLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  if (loading) return <LoadingSpinner />;

  return (
    <div className="space-y-6">
      {cacheMetrics && (
        <Card>
          <CardHeader title="Prompt Cache Performance" />
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div>
                <p className="text-sm text-theme-muted">Hit Rate</p>
                <p className="text-xl font-bold text-theme-primary">{cacheMetrics.hit_rate}%</p>
              </div>
              <div>
                <p className="text-sm text-theme-muted">Hits</p>
                <p className="text-xl font-bold text-theme-success">{cacheMetrics.hits}</p>
              </div>
              <div>
                <p className="text-sm text-theme-muted">Misses</p>
                <p className="text-xl font-bold text-theme-warning">{cacheMetrics.misses}</p>
              </div>
              <div>
                <p className="text-sm text-theme-muted">Est. Savings</p>
                <p className="text-xl font-bold text-theme-primary">${cacheMetrics.estimated_savings_usd}</p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader title="Agent Quality Trends" />
        <CardContent>
          {agentTrends.length === 0 ? (
            <div className="text-center py-8 text-theme-muted">
              <BarChart3 className="w-8 h-8 mx-auto mb-2 opacity-50" />
              <p className="text-sm">No evaluation data available yet</p>
            </div>
          ) : (
            <div className="space-y-3">
              {agentTrends.map((agent) => (
                <div
                  key={agent.agent_id}
                  className="flex items-center justify-between p-3 rounded-lg bg-theme-surface border border-theme-border"
                >
                  <div className="flex items-center gap-3">
                    <TrendIcon trend={agent.trend} />
                    <div>
                      <p className="text-sm font-medium text-theme-primary">{agent.agent_name}</p>
                      <p className="text-xs text-theme-muted">{agent.count} evaluations</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-4 text-xs">
                    {agent.average_correctness !== null && (
                      <div className="text-center">
                        <p className="text-theme-muted">Correct</p>
                        <p className="font-medium text-theme-primary">{agent.average_correctness}/5</p>
                      </div>
                    )}
                    {agent.average_helpfulness !== null && (
                      <div className="text-center">
                        <p className="text-theme-muted">Helpful</p>
                        <p className="font-medium text-theme-primary">{agent.average_helpfulness}/5</p>
                      </div>
                    )}
                    <Badge variant={agent.trend === 'improving' ? 'success' : agent.trend === 'declining' ? 'danger' : 'default'}>
                      {agent.trend}
                    </Badge>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
};
