import React, { useState, useCallback, useEffect } from 'react';
import { FileText, Filter } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { fetchEvaluationResults } from '../api/evaluationApi';
import type { EvaluationResult, ScoreDimension } from '../types/evaluation';
import { SCORE_DIMENSIONS, DIMENSION_LABELS } from '../types/evaluation';

interface EvalResultsViewerProps {
  agentId?: string;
}

const ScoreBar: React.FC<{ score: number | null; label: string }> = ({ score, label }) => {
  if (score === null || score === undefined) return null;
  const width = (score / 5) * 100;
  const color = score >= 4 ? 'bg-theme-success' : score >= 3 ? 'bg-theme-warning' : 'bg-theme-error';

  return (
    <div className="flex items-center gap-2">
      <span className="text-xs text-theme-muted w-24">{label}</span>
      <div className="flex-1 h-2 bg-theme-surface-hover rounded-full overflow-hidden">
        <div className={`h-full rounded-full ${color}`} style={{ width: `${width}%` }} />
      </div>
      <span className="text-xs font-medium text-theme-primary w-8 text-right">{score}/5</span>
    </div>
  );
};

export const EvalResultsViewer: React.FC<EvalResultsViewerProps> = ({ agentId }) => {
  const [loading, setLoading] = useState(true);
  const [results, setResults] = useState<EvaluationResult[]>([]);
  const [selectedDimension, setSelectedDimension] = useState<ScoreDimension | 'all'>('all');
  const { addNotification } = useNotifications();

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const data = await fetchEvaluationResults({ agent_id: agentId, limit: 100 });
      setResults(data);
    } catch {
      addNotification({ type: 'error', message: 'Failed to load evaluation results' });
    } finally {
      setLoading(false);
    }
  }, [agentId, addNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  if (loading) return <LoadingSpinner />;

  const avgScores: Record<ScoreDimension, number | null> = {
    correctness: null,
    completeness: null,
    helpfulness: null,
    safety: null,
  };

  if (results.length > 0) {
    for (const dim of SCORE_DIMENSIONS) {
      const validScores = results.filter((r) => r[dim] !== null).map((r) => r[dim] as number);
      avgScores[dim] = validScores.length > 0
        ? Math.round((validScores.reduce((a, b) => a + b, 0) / validScores.length) * 10) / 10
        : null;
    }
  }

  const filteredResults = selectedDimension === 'all'
    ? results
    : results.filter((r) => r[selectedDimension] !== null);

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader title="Score Averages" />
        <CardContent>
          {results.length === 0 ? (
            <p className="text-sm text-theme-muted text-center py-4">No evaluation results yet</p>
          ) : (
            <div className="space-y-3">
              {SCORE_DIMENSIONS.map((dim) => (
                <ScoreBar key={dim} score={avgScores[dim]} label={DIMENSION_LABELS[dim]} />
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader title={`Results (${filteredResults.length})`} />
        <CardContent>
          <div className="flex items-center gap-2 mb-4">
            <Filter className="w-4 h-4 text-theme-muted" />
            <select
              value={selectedDimension}
              onChange={(e) => setSelectedDimension(e.target.value as ScoreDimension | 'all')}
              className="text-sm bg-theme-surface border border-theme-border rounded px-2 py-1 text-theme-primary"
            >
              <option value="all">All Dimensions</option>
              {SCORE_DIMENSIONS.map((dim) => (
                <option key={dim} value={dim}>{DIMENSION_LABELS[dim]}</option>
              ))}
            </select>
          </div>

          {filteredResults.length === 0 ? (
            <div className="text-center py-8 text-theme-muted">
              <FileText className="w-8 h-8 mx-auto mb-2 opacity-50" />
              <p className="text-sm">No results match the filter</p>
            </div>
          ) : (
            <div className="space-y-3">
              {filteredResults.map((result) => (
                <div
                  key={result.id}
                  className="p-4 rounded-lg bg-theme-surface border border-theme-border"
                >
                  <div className="flex items-start justify-between mb-2">
                    <div className="flex items-center gap-2">
                      <Badge variant={
                        (result.average ?? 0) >= 4 ? 'success' :
                        (result.average ?? 0) >= 3 ? 'warning' : 'danger'
                      }>
                        Avg: {result.average?.toFixed(1) ?? 'N/A'}
                      </Badge>
                      <span className="text-xs text-theme-muted">
                        {result.evaluator_model}
                      </span>
                    </div>
                    <span className="text-xs text-theme-muted">
                      {new Date(result.created_at).toLocaleDateString()}
                    </span>
                  </div>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-2 mb-2">
                    {SCORE_DIMENSIONS.map((dim) => (
                      result[dim] !== null && (
                        <div key={dim} className="text-center">
                          <p className="text-xs text-theme-muted">{DIMENSION_LABELS[dim]}</p>
                          <p className="text-sm font-medium text-theme-primary">{result[dim]}/5</p>
                        </div>
                      )
                    ))}
                  </div>
                  {result.feedback && (
                    <p className="text-xs text-theme-secondary mt-2 line-clamp-2">{result.feedback}</p>
                  )}
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
};
