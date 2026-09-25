import React from 'react';
import { Gauge, Radio, Users } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EntityLink } from '@/shared/components/entity';
import { intelligenceApi } from '@/shared/services/ai/IntelligenceApiService';
import type {
  StigmergicSignal, PressureField, TeamRestructureEvent, CoordinationSummary,
} from '@/shared/services/ai/IntelligenceApiService';

const getSignalTypeColor = (t: string) => {
  switch (t) {
    case 'pheromone': return 'success';
    case 'pressure': return 'warning';
    case 'beacon': return 'info';
    case 'warning': return 'danger';
    case 'discovery': return 'primary';
    default: return 'secondary';
  }
};

const getFieldTypeLabel = (t: string) => t.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());

const CoordinationContent: React.FC<{
  coordSummary: CoordinationSummary | null;
  signals: StigmergicSignal[];
  pressureFields: PressureField[];
  teamEvents: TeamRestructureEvent[];
  loading: boolean;
}> = ({ coordSummary, signals, pressureFields, teamEvents, loading }) => {
  if (loading) return <LoadingSpinner size="sm" className="py-8" />;

  return (
    <div className="space-y-6">
      {/* Summary */}
      {coordSummary && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-success-fg">{coordSummary.signals.active}</div>
            <div className="text-xs text-theme-tertiary">Active Signals</div>
            <div className="text-xs text-theme-secondary mt-1">{coordSummary.signals.fading} fading</div>
          </Card>
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-warning-fg">{coordSummary.pressure_fields.actionable}</div>
            <div className="text-xs text-theme-tertiary">Actionable Pressures</div>
            <div className="text-xs text-theme-secondary mt-1">Avg: {(coordSummary.pressure_fields.avg_pressure * 100).toFixed(0)}%</div>
          </Card>
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-primary">{coordSummary.pressure_fields.total}</div>
            <div className="text-xs text-theme-tertiary">Pressure Fields</div>
          </Card>
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-info-fg">{coordSummary.team_events.recent_24h}</div>
            <div className="text-xs text-theme-tertiary">Team Events (24h)</div>
            <div className="text-xs text-theme-secondary mt-1">{coordSummary.team_events.total} total</div>
          </Card>
        </div>
      )}

      {/* Stigmergic Signals */}
      <Card className="p-6">
        <div className="flex items-center gap-2 mb-4">
          <Radio size={18} className="text-theme-success-fg" />
          <h3 className="text-lg font-medium text-theme-primary">Stigmergic Signals</h3>
          <Badge variant="secondary" size="sm">{signals.length}</Badge>
        </div>
        {signals.length === 0 ? (
          <p className="text-sm text-theme-tertiary">No active signals. Agents emit signals to coordinate behavior indirectly.</p>
        ) : (
          <div className="space-y-3">
            {signals.map(s => (
              <div key={s.id} className="border border-theme rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Badge variant={getSignalTypeColor(s.signal_type) as 'success' | 'warning' | 'info' | 'danger'} size="sm">{s.signal_type}</Badge>
                    <span className="text-sm font-medium text-theme-primary">{s.signal_key}</span>
                  </div>
                  <div className="flex items-center gap-3 text-xs">
                    <span className="text-theme-secondary">Strength: <strong>{(s.strength * 100).toFixed(0)}%</strong></span>
                    <span className="text-theme-tertiary">{s.reinforce_count} reinforced</span>
                    <span className="text-theme-tertiary">{s.perceive_count} perceived</span>
                  </div>
                </div>
                {s.emitter_agent && <span className="text-xs text-theme-info-fg">Emitted by <EntityLink type="agent" id={s.emitter_agent.id} label={s.emitter_agent.name} /></span>}
                {/* Strength bar */}
                <div className="mt-2 h-1.5 bg-theme-surface-secondary rounded-full overflow-hidden">
                  <div className="h-full bg-theme-success-bg rounded-full transition-all" style={{ width: `${s.strength * 100}%` }} />
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* Pressure Fields */}
      <Card className="p-6">
        <div className="flex items-center gap-2 mb-4">
          <Gauge size={18} className="text-theme-warning-fg" />
          <h3 className="text-lg font-medium text-theme-primary">Pressure Fields</h3>
          <Badge variant="secondary" size="sm">{pressureFields.length}</Badge>
        </div>
        {pressureFields.length === 0 ? (
          <p className="text-sm text-theme-tertiary">No pressure fields measured. Fields detect quality gradients that guide agent behavior.</p>
        ) : (
          <div className="space-y-3">
            {pressureFields.map(f => (
              <div key={f.id} className="border border-theme rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Badge variant={f.actionable ? 'warning' : 'secondary'} size="sm">{getFieldTypeLabel(f.field_type)}</Badge>
                    <span className="text-sm text-theme-primary">{f.artifact_ref}</span>
                  </div>
                  <div className="flex items-center gap-3 text-xs">
                    <span className={f.actionable ? 'text-theme-warning-fg font-medium' : 'text-theme-secondary'}>
                      Pressure: {(f.pressure_value * 100).toFixed(0)}%
                    </span>
                    <span className="text-theme-tertiary">Threshold: {(f.threshold * 100).toFixed(0)}%</span>
                    <span className="text-theme-tertiary">Addressed {f.address_count}x</span>
                  </div>
                </div>
                <div className="mt-2 h-1.5 bg-theme-surface-secondary rounded-full overflow-hidden relative">
                  <div className="h-full rounded-full transition-all" style={{
                    width: `${f.pressure_value * 100}%`,
                    backgroundColor: f.actionable ? 'var(--color-warning)' : 'var(--color-info)'
                  }} />
                  {/* Threshold marker */}
                  <div className="absolute top-0 h-full w-0.5 bg-theme-error-bg" style={{ left: `${f.threshold * 100}%` }} />
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* Team Restructure Events */}
      <Card className="p-6">
        <div className="flex items-center gap-2 mb-4">
          <Users size={18} className="text-theme-info-fg" />
          <h3 className="text-lg font-medium text-theme-primary">Team Restructure Events</h3>
          <Badge variant="secondary" size="sm">{teamEvents.length}</Badge>
        </div>
        {teamEvents.length === 0 ? (
          <p className="text-sm text-theme-tertiary">No team restructure events. Events occur when teams dynamically adapt their structure.</p>
        ) : (
          <div className="space-y-3">
            {teamEvents.map(e => (
              <div key={e.id} className="border border-theme rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Badge variant="info" size="sm">{e.event_type.replace(/_/g, ' ')}</Badge>
                    {e.team && <span className="text-sm text-theme-primary"><EntityLink type="agent_team" id={e.team.id} label={e.team.name} /></span>}
                    {e.agent && <span className="text-xs text-theme-secondary">(<EntityLink type="agent" id={e.agent.id} label={e.agent.name} />)</span>}
                  </div>
                  <span className="text-xs text-theme-tertiary">{new Date(e.created_at).toLocaleDateString()}</span>
                </div>
                {e.rationale && Object.keys(e.rationale).length > 0 && (
                  <p className="text-xs text-theme-secondary">{JSON.stringify(e.rationale).slice(0, 200)}</p>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
};

/**
 * How teams coordinate: stigmergic signals, pressure fields and team
 * restructure events (AI → Teams → Coordination). Moved from the Governance
 * page; the endpoints are gated on ai.manage.
 */
export const CoordinationPanel: React.FC = () => {
  const { data, isLoading } = useQuery({
    queryKey: ['teams', 'coordination'],
    queryFn: async () => {
      const [summaryRes, signalsRes, fieldsRes, eventsRes] = await Promise.all([
        intelligenceApi.getCoordinationSummary().catch(() => ({ summary: null })),
        intelligenceApi.getSignals({ active: 'true' }).catch(() => ({ items: [] })),
        intelligenceApi.getPressureFields().catch(() => ({ items: [] })),
        intelligenceApi.getTeamEvents().catch(() => ({ items: [] })),
      ]);
      return {
        coordSummary: summaryRes.summary || null,
        signals: signalsRes.items || [],
        pressureFields: fieldsRes.items || [],
        teamEvents: eventsRes.items || [],
      };
    },
  });

  return (
    <CoordinationContent
      coordSummary={data?.coordSummary ?? null}
      signals={data?.signals ?? []}
      pressureFields={data?.pressureFields ?? []}
      teamEvents={data?.teamEvents ?? []}
      loading={isLoading}
    />
  );
};
