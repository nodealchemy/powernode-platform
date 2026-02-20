import { useState, useEffect } from 'react';
import { Activity, Loader2 } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { skillLifecycleApi } from '../services/skillLifecycleApi';
import type { SkillHealthMetricsData } from '../types/lifecycle';

const GRADE_COLORS: Record<string, string> = {
  A: 'text-theme-success',
  B: 'text-theme-info',
  C: 'text-theme-warning',
  D: 'text-theme-warning',
  F: 'text-theme-error',
};

interface GaugeProps {
  label: string;
  value: number;
  maxValue?: number;
}

function Gauge({ label, value, maxValue = 1 }: GaugeProps) {
  const pct = Math.round((value / maxValue) * 100);
  const color = pct >= 80 ? 'bg-theme-success' : pct >= 60 ? 'bg-theme-info' : pct >= 40 ? 'bg-theme-warning' : 'bg-theme-error';

  return (
    <div>
      <div className="flex justify-between text-xs mb-1">
        <span className="text-theme-secondary">{label}</span>
        <span className="text-theme-tertiary">{pct}%</span>
      </div>
      <div className="h-2 bg-theme-surface-secondary rounded-full overflow-hidden">
        <div className={`h-full ${color} rounded-full transition-all`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

export function SkillHealthMetrics() {
  const [health, setHealth] = useState<SkillHealthMetricsData | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      const response = await skillLifecycleApi.getHealth();
      if (response.success && response.data) {
        setHealth(response.data.health);
      }
      setLoading(false);
    };
    load();
  }, []);

  if (loading) {
    return (
      <div className="flex justify-center py-8">
        <Loader2 className="w-6 h-6 animate-spin text-theme-tertiary" />
      </div>
    );
  }

  if (!health) {
    return <div className="text-center py-8 text-theme-tertiary text-sm">Unable to load health metrics</div>;
  }

  return (
    <div className="space-y-4" data-testid="skill-health-metrics">
      {/* Score & Grade */}
      <Card variant="outlined" padding="md">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Activity className="w-5 h-5 text-theme-secondary" />
            <div>
              <p className="text-sm text-theme-secondary">Skill Graph Health</p>
              <p className="text-2xl font-bold text-theme-primary">{Math.round(health.score)}/100</p>
            </div>
          </div>
          <div className={`text-4xl font-bold ${GRADE_COLORS[health.grade] || 'text-theme-primary'}`}>
            {health.grade}
          </div>
        </div>
      </Card>

      {/* Component Gauges */}
      <Card variant="outlined" padding="md">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Score Components</h4>
        <div className="space-y-3">
          <Gauge label="Coverage" value={health.components.coverage} />
          <Gauge label="Connectivity" value={health.components.connectivity} />
          <Gauge label="Freshness" value={health.components.freshness} />
          <Gauge label="Effectiveness" value={health.components.effectiveness} />
          {health.components.conflict_penalty > 0 && (
            <div>
              <div className="flex justify-between text-xs mb-1">
                <span className="text-theme-error">Conflict Penalty</span>
                <span className="text-theme-error">-{Math.round(health.components.conflict_penalty * 100)}%</span>
              </div>
              <div className="h-2 bg-theme-surface-secondary rounded-full overflow-hidden">
                <div
                  className="h-full bg-theme-error rounded-full transition-all"
                  style={{ width: `${Math.round(health.components.conflict_penalty * 100)}%` }}
                />
              </div>
            </div>
          )}
        </div>
      </Card>

      {/* Stats */}
      {health.stats && (
        <Card variant="outlined" padding="md">
          <h4 className="text-sm font-medium text-theme-primary mb-3">Graph Statistics</h4>
          <div className="grid grid-cols-2 gap-3">
            {[
              { label: 'Total Skills', value: health.stats.total_skills },
              { label: 'Active Skills', value: health.stats.active_skills },
              { label: 'Graph Nodes', value: health.stats.total_nodes },
              { label: 'Graph Edges', value: health.stats.total_edges },
              { label: 'Active Conflicts', value: health.stats.active_conflicts },
            ].map((stat) => (
              <div key={stat.label} className="text-center">
                <p className="text-lg font-semibold text-theme-primary">{stat.value}</p>
                <p className="text-xs text-theme-tertiary">{stat.label}</p>
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  );
}
