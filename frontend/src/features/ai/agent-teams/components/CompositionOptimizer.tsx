import React, { useState, useEffect } from 'react';
import { Zap, AlertTriangle, CheckCircle, TrendingUp, Loader2 } from 'lucide-react';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { agentTeamsApi } from '../services/agentTeamsApi';

interface OptimizationResult {
  skill_coverage: number;
  gaps: string[];
  redundancies: string[];
  recommendations: { agent_type: string; reason: string }[];
}

interface CompositionOptimizerProps {
  teamId: string;
}

export const CompositionOptimizer: React.FC<CompositionOptimizerProps> = ({ teamId }) => {
  const [data, setData] = useState<OptimizationResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [optimizing, setOptimizing] = useState(false);
  const { confirm, ConfirmationDialog } = useConfirmation();

  useEffect(() => {
    const fetchData = async () => {
      try {
        const result = await agentTeamsApi.optimizeTeam(teamId);
        setData(result);
      } catch {
        // Silently handle
      } finally {
        setLoading(false);
      }
    };
    fetchData();
  }, [teamId]);

  const handleAutoOptimize = () => {
    confirm({
      title: 'Auto-Optimize Team',
      message: 'This will automatically adjust the team composition based on detected skill gaps and redundancies. Continue?',
      confirmLabel: 'Optimize',
      variant: 'warning',
      onConfirm: async () => {
        setOptimizing(true);
        try {
          const result = await agentTeamsApi.optimizeTeam(teamId);
          setData(result);
        } catch {
          // Error handled by API
        } finally {
          setOptimizing(false);
        }
      }
    });
  };

  if (loading) {
    return (
      <div className="bg-theme-surface border border-theme rounded-lg p-4 flex items-center justify-center">
        <Loader2 className="h-5 w-5 animate-spin text-theme-primary" />
      </div>
    );
  }

  if (!data) return null;

  const coveragePercent = Math.round(data.skill_coverage * 100);

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4 space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <TrendingUp className="h-4 w-4 text-theme-primary" />
          <h4 className="text-sm font-semibold text-theme-primary">Composition Optimizer</h4>
        </div>
        <button
          type="button"
          onClick={handleAutoOptimize}
          disabled={optimizing}
          className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-theme-primary bg-theme-primary/10 rounded-md hover:bg-theme-primary/20 transition-colors disabled:opacity-50"
        >
          {optimizing ? <Loader2 className="h-3 w-3 animate-spin" /> : <Zap className="h-3 w-3" />}
          Auto-Optimize
        </button>
      </div>

      {/* Skill Coverage Bar */}
      <div>
        <div className="flex items-center justify-between mb-1">
          <span className="text-xs text-theme-secondary">Skill Coverage</span>
          <span className={`text-xs font-medium ${
            coveragePercent >= 80 ? 'text-theme-success' : coveragePercent >= 50 ? 'text-theme-warning' : 'text-theme-danger'
          }`}>
            {coveragePercent}%
          </span>
        </div>
        <div className="w-full bg-theme-accent rounded-full h-2">
          <div
            className={`h-2 rounded-full transition-all ${
              coveragePercent >= 80 ? 'bg-theme-success' : coveragePercent >= 50 ? 'bg-theme-warning' : 'bg-theme-danger-solid'
            }`}
            style={{ width: `${coveragePercent}%` }}
          />
        </div>
      </div>

      {/* Gaps */}
      {data.gaps.length > 0 && (
        <div>
          <h5 className="text-xs font-medium text-theme-secondary mb-1">Skill Gaps</h5>
          <div className="space-y-1">
            {data.gaps.map((gap, idx) => (
              <div key={idx} className="flex items-center gap-2 text-xs">
                <AlertTriangle className="h-3 w-3 text-theme-warning flex-shrink-0" />
                <span className="text-theme-primary">{gap}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Redundancies */}
      {data.redundancies.length > 0 && (
        <div>
          <h5 className="text-xs font-medium text-theme-secondary mb-1">Redundancies</h5>
          <div className="space-y-1">
            {data.redundancies.map((r, idx) => (
              <div key={idx} className="flex items-center gap-2 text-xs">
                <AlertTriangle className="h-3 w-3 text-theme-info flex-shrink-0" />
                <span className="text-theme-secondary">{r}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Recommendations */}
      {data.recommendations.length > 0 && (
        <div>
          <h5 className="text-xs font-medium text-theme-secondary mb-1">Recommendations</h5>
          <div className="space-y-2">
            {data.recommendations.map((rec, idx) => (
              <div key={idx} className="p-2 bg-theme-primary/5 border border-theme rounded-md">
                <div className="flex items-center gap-2">
                  <CheckCircle className="h-3 w-3 text-theme-success flex-shrink-0" />
                  <span className="text-xs font-medium text-theme-primary">{rec.agent_type}</span>
                </div>
                <p className="text-xs text-theme-secondary mt-1 ml-5">{rec.reason}</p>
              </div>
            ))}
          </div>
        </div>
      )}

      {ConfirmationDialog}
    </div>
  );
};
