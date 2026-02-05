// Composition Health Banner - Shows real-time team composition analysis
import React, { useEffect, useState } from 'react';
import { AlertTriangle, CheckCircle, XCircle, ChevronDown, ChevronUp, Users } from 'lucide-react';
import teamsApi from '@/shared/services/ai/TeamsApiService';
import type { CompositionHealth } from '@/shared/services/ai/TeamsApiService';

interface CompositionHealthBannerProps {
  teamId: string;
  onHealthChange?: (health: CompositionHealth) => void;
}

export const CompositionHealthBanner: React.FC<CompositionHealthBannerProps> = ({
  teamId,
  onHealthChange
}) => {
  const [health, setHealth] = useState<CompositionHealth | null>(null);
  const [loading, setLoading] = useState(false);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    if (!teamId) return;
    fetchHealth();
  }, [teamId]);

  const fetchHealth = async () => {
    setLoading(true);
    try {
      const data = await teamsApi.getCompositionHealth(teamId);
      setHealth(data);
      onHealthChange?.(data);
    } catch {
      // Silently fail - health check is informational
    } finally {
      setLoading(false);
    }
  };

  if (loading || !health) return null;

  const getStatusIcon = () => {
    switch (health.status) {
      case 'healthy':
        return <CheckCircle className="text-theme-success" size={18} />;
      case 'warning':
        return <AlertTriangle className="text-theme-warning" size={18} />;
      case 'unhealthy':
        return <XCircle className="text-theme-danger" size={18} />;
    }
  };

  const getStatusColor = () => {
    switch (health.status) {
      case 'healthy':
        return 'border-theme-success/30 bg-theme-success/5';
      case 'warning':
        return 'border-theme-warning/30 bg-theme-warning/5';
      case 'unhealthy':
        return 'border-theme-danger/30 bg-theme-error/5';
    }
  };

  const getStatusText = () => {
    switch (health.status) {
      case 'healthy':
        return 'Healthy';
      case 'warning':
        return 'Warning';
      case 'unhealthy':
        return 'Unhealthy';
    }
  };

  // Ratio bar: optimal range is 2-5
  const ratioPercentage = Math.min((health.workers_per_lead / 10) * 100, 100);
  const isOptimalRange = health.workers_per_lead >= 2 && health.workers_per_lead <= 5;

  return (
    <div className={`border rounded-lg p-4 mb-4 ${getStatusColor()}`} data-testid="composition-health-banner">
      {/* Header */}
      <div
        className="flex items-center justify-between cursor-pointer"
        onClick={() => setExpanded(!expanded)}
      >
        <div className="flex items-center gap-3">
          <Users size={18} className="text-theme-secondary" />
          <span className="text-sm font-medium text-theme-primary">
            Team Composition Health
          </span>
        </div>

        <div className="flex items-center gap-3">
          {getStatusIcon()}
          <span className={`text-sm font-medium ${
            health.status === 'healthy' ? 'text-theme-success' :
            health.status === 'warning' ? 'text-theme-warning' :
            'text-theme-danger'
          }`}>
            {getStatusText()}
          </span>
          {expanded ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
        </div>
      </div>

      {/* Stats Row */}
      <div className="flex gap-6 mt-3 text-xs text-theme-secondary">
        <span>Members: <span className="font-medium text-theme-primary">{health.member_count}</span></span>
        <span>Leads: <span className="font-medium text-theme-primary">{health.lead_count}</span></span>
        <span>Workers: <span className="font-medium text-theme-primary">{health.worker_count}</span></span>
        <span>Ratio: <span className="font-medium text-theme-primary">{health.workers_per_lead}:1</span></span>
      </div>

      {/* Ratio Bar */}
      {health.lead_count > 0 && (
        <div className="mt-3">
          <div className="flex items-center justify-between text-xs text-theme-secondary mb-1">
            <span>Workers per Lead</span>
            <span>{isOptimalRange ? 'Optimal (2-5)' : health.workers_per_lead > 5 ? 'High' : 'Low'}</span>
          </div>
          <div className="w-full bg-theme-accent rounded-full h-2">
            <div
              className={`h-2 rounded-full transition-all duration-300 ${
                isOptimalRange ? 'bg-theme-success' :
                health.workers_per_lead > 9 ? 'bg-theme-danger-solid' :
                'bg-theme-warning'
              }`}
              style={{ width: `${ratioPercentage}%` }}
            />
          </div>
        </div>
      )}

      {/* Expanded Details */}
      {expanded && (
        <div className="mt-4 space-y-3">
          {/* Warnings */}
          {health.warnings.length > 0 && (
            <div>
              <h4 className="text-xs font-medium text-theme-warning mb-1">Warnings</h4>
              <ul className="space-y-1">
                {health.warnings.map((warning, idx) => (
                  <li key={idx} className="flex items-start gap-2 text-xs text-theme-secondary">
                    <AlertTriangle size={12} className="text-theme-warning mt-0.5 shrink-0" />
                    {warning}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {/* Recommendations */}
          {health.recommendations.length > 0 && (
            <div>
              <h4 className="text-xs font-medium text-theme-info mb-1">Recommendations</h4>
              <ul className="space-y-1">
                {health.recommendations.map((rec, idx) => (
                  <li key={idx} className="flex items-start gap-2 text-xs text-theme-secondary">
                    <CheckCircle size={12} className="text-theme-info mt-0.5 shrink-0" />
                    {rec}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
