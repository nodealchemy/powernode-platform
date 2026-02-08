import React, { useState, useEffect } from 'react';
import { Zap, AlertTriangle, CheckCircle, TrendingUp, Loader2 } from 'lucide-react';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { agentTeamsApi } from '../services/agentTeamsApi';

interface CompositionHealth {
  status: string;
  member_count: number;
  lead_count: number;
  worker_count: number;
  workers_per_lead: number;
  warnings: string[];
  recommendations: string[];
}

interface CompositionOptimizerProps {
  teamId: string;
}

export const CompositionOptimizer: React.FC<CompositionOptimizerProps> = ({ teamId }) => {
  const [data, setData] = useState<CompositionHealth | null>(null);
  const [loading, setLoading] = useState(true);
  const [optimizing, setOptimizing] = useState(false);
  const { confirm, ConfirmationDialog } = useConfirmation();

  const fetchHealth = async () => {
    try {
      const result = await agentTeamsApi.getCompositionHealth(teamId);
      setData(result);
    } catch {
      // Silently handle
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchHealth();
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
          await agentTeamsApi.optimizeTeam(teamId);
          await fetchHealth();
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

  const statusColor = data.status === 'healthy' ? 'text-theme-success' : data.status === 'warning' ? 'text-theme-warning' : 'text-theme-danger';

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4 space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <TrendingUp className="h-4 w-4 text-theme-primary" />
          <h4 className="text-sm font-semibold text-theme-primary">Composition Health</h4>
          <span className={`text-xs font-medium capitalize ${statusColor}`}>{data.status}</span>
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

      {/* Team Stats */}
      <div className="grid grid-cols-3 gap-2">
        <div className="text-center p-2 bg-theme-primary/5 rounded">
          <div className="text-lg font-semibold text-theme-primary">{data.member_count}</div>
          <div className="text-xs text-theme-secondary">Members</div>
        </div>
        <div className="text-center p-2 bg-theme-primary/5 rounded">
          <div className="text-lg font-semibold text-theme-primary">{data.lead_count}</div>
          <div className="text-xs text-theme-secondary">Leads</div>
        </div>
        <div className="text-center p-2 bg-theme-primary/5 rounded">
          <div className="text-lg font-semibold text-theme-primary">{data.workers_per_lead}:1</div>
          <div className="text-xs text-theme-secondary">Worker Ratio</div>
        </div>
      </div>

      {/* Warnings */}
      {data.warnings.length > 0 && (
        <div>
          <h5 className="text-xs font-medium text-theme-secondary mb-1">Warnings</h5>
          <div className="space-y-1">
            {data.warnings.map((warning, idx) => (
              <div key={idx} className="flex items-center gap-2 text-xs">
                <AlertTriangle className="h-3 w-3 text-theme-warning flex-shrink-0" />
                <span className="text-theme-primary">{warning}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Recommendations */}
      {data.recommendations.length > 0 && (
        <div>
          <h5 className="text-xs font-medium text-theme-secondary mb-1">Recommendations</h5>
          <div className="space-y-1">
            {data.recommendations.map((rec, idx) => (
              <div key={idx} className="flex items-center gap-2 text-xs">
                <CheckCircle className="h-3 w-3 text-theme-success flex-shrink-0" />
                <span className="text-theme-primary">{rec}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {ConfirmationDialog}
    </div>
  );
};
