import React, { useState, useCallback, useEffect } from 'react';
import { BarChart3 } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { fetchAgentTrends } from '../api/evaluationApi';
import type { AgentScoreTrend, ScoreDimension } from '../types/evaluation';
import { SCORE_DIMENSIONS, DIMENSION_LABELS } from '../types/evaluation';

export const EvalComparison: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [trends, setTrends] = useState<AgentScoreTrend[]>([]);
  const [selectedAgents, setSelectedAgents] = useState<string[]>([]);
  const { addNotification } = useNotifications();

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const data = await fetchAgentTrends();
      setTrends(data);
      if (data.length > 0) {
        setSelectedAgents(data.slice(0, 4).map((t) => t.agent_id));
      }
    } catch {
      addNotification({ type: 'error', message: 'Failed to load agent trends' });
    } finally {
      setLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const toggleAgent = (agentId: string) => {
    setSelectedAgents((prev) =>
      prev.includes(agentId)
        ? prev.filter((id) => id !== agentId)
        : [...prev, agentId]
    );
  };

  if (loading) return <LoadingSpinner />;

  const compared = trends.filter((t) => selectedAgents.includes(t.agent_id));

  const maxScore = (dim: ScoreDimension) => {
    const scores = compared
      .map((t) => t[`average_${dim}` as keyof AgentScoreTrend] as number | null)
      .filter((s): s is number => s !== null);
    return scores.length > 0 ? Math.max(...scores) : 0;
  };

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader title="Select Agents to Compare" />
        <CardContent>
          {trends.length === 0 ? (
            <p className="text-sm text-theme-muted text-center py-4">No agents with evaluation data</p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {trends.map((t) => (
                <button
                  key={t.agent_id}
                  onClick={() => toggleAgent(t.agent_id)}
                  className={`px-3 py-1.5 text-sm rounded-full border transition-colors ${
                    selectedAgents.includes(t.agent_id)
                      ? 'bg-theme-primary text-white border-theme-primary'
                      : 'bg-theme-surface text-theme-secondary border-theme-border hover:border-theme-primary'
                  }`}
                >
                  {t.agent_name} ({t.count})
                </button>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {compared.length >= 2 && (
        <Card>
          <CardHeader title="Side-by-Side Comparison" />
          <CardContent>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-theme-border">
                    <th className="text-left py-2 px-3 text-theme-muted font-medium">Dimension</th>
                    {compared.map((agent) => (
                      <th key={agent.agent_id} className="text-center py-2 px-3 text-theme-primary font-medium">
                        {agent.agent_name}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {SCORE_DIMENSIONS.map((dim) => {
                    const best = maxScore(dim);
                    return (
                      <tr key={dim} className="border-b border-theme-border last:border-0">
                        <td className="py-2 px-3 text-theme-secondary">{DIMENSION_LABELS[dim]}</td>
                        {compared.map((agent) => {
                          const score = agent[`average_${dim}` as keyof AgentScoreTrend] as number | null;
                          const isBest = score !== null && score === best && compared.length > 1;
                          return (
                            <td key={agent.agent_id} className="text-center py-2 px-3">
                              {score !== null ? (
                                <span className={`font-medium ${isBest ? 'text-theme-success' : 'text-theme-primary'}`}>
                                  {score.toFixed(1)}/5
                                  {isBest && <span className="text-xs ml-1">★</span>}
                                </span>
                              ) : (
                                <span className="text-theme-muted">-</span>
                              )}
                            </td>
                          );
                        })}
                      </tr>
                    );
                  })}
                  <tr className="border-t-2 border-theme-border">
                    <td className="py-2 px-3 font-medium text-theme-secondary">Trend</td>
                    {compared.map((agent) => (
                      <td key={agent.agent_id} className="text-center py-2 px-3">
                        <Badge variant={
                          agent.trend === 'improving' ? 'success' :
                          agent.trend === 'declining' ? 'danger' : 'default'
                        }>
                          {agent.trend}
                        </Badge>
                      </td>
                    ))}
                  </tr>
                  <tr>
                    <td className="py-2 px-3 text-theme-muted">Evaluations</td>
                    {compared.map((agent) => (
                      <td key={agent.agent_id} className="text-center py-2 px-3 text-theme-muted">
                        {agent.count}
                      </td>
                    ))}
                  </tr>
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}

      {compared.length < 2 && trends.length >= 2 && (
        <Card>
          <CardContent className="p-8 text-center text-theme-muted">
            <BarChart3 className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>Select at least 2 agents to compare their evaluation scores side-by-side.</p>
          </CardContent>
        </Card>
      )}
    </div>
  );
};
