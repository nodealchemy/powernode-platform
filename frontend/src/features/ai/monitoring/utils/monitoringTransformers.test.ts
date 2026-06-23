import { transformDashboardData, transformAlerts } from './monitoringTransformers';
import type { MonitoringDashboard, Alert as ApiAlert } from '@/shared/services/ai/MonitoringApiService';

const dashboard = (overrides: Record<string, unknown>): MonitoringDashboard =>
  overrides as unknown as MonitoringDashboard;

const apiAlert = (overrides: Partial<ApiAlert>): ApiAlert =>
  ({
    id: 'a1',
    severity: 'info',
    component: 'worker',
    message: 'Something happened',
    acknowledged: false,
    resolved: false,
    timestamp: '2024-01-01T00:00:00.000Z',
    ...overrides,
  } as unknown as ApiAlert);

describe('transformDashboardData', () => {
  it('prefers overview.active_agents, falling back to agents.total then 0', () => {
    expect(transformDashboardData(dashboard({ overview: { active_agents: 5 }, agents: { total: 3 } }))
      .overview.total_agents).toBe(5);
    expect(transformDashboardData(dashboard({ overview: {}, agents: { total: 3 } }))
      .overview.total_agents).toBe(3);
    expect(transformDashboardData(dashboard({})).overview.total_agents).toBe(0);
  });

  it('derives total_providers from providers length (0 when absent)', () => {
    expect(transformDashboardData(dashboard({ providers: [{}, {}] })).overview.total_providers).toBe(2);
    expect(transformDashboardData(dashboard({})).overview.total_providers).toBe(0);
  });

  it('passes through extended overview metrics with 0 fallbacks', () => {
    const d = transformDashboardData(
      dashboard({ overview: { total_executions_today: 12, total_cost_today: 3.5, avg_response_time: 200, success_rate: 0.99 } })
    );
    expect(d.overview.total_executions_today).toBe(12);
    expect(d.overview.total_cost_today).toBe(3.5);
    expect(d.overview.avg_response_time).toBe(200);
    expect(d.overview.success_rate).toBe(0.99);
    expect(transformDashboardData(dashboard({})).overview.success_rate).toBe(0);
  });

  it('uses system_health.uptime_percentage for health_score, defaulting to 100', () => {
    expect(transformDashboardData(dashboard({ system_health: { uptime_percentage: 87 } })).health_score).toBe(87);
    expect(transformDashboardData(dashboard({})).health_score).toBe(100);
  });
});

describe('transformAlerts', () => {
  it('remaps severity (critical->critical, warning->high, else->medium)', () => {
    expect(transformAlerts([apiAlert({ severity: 'critical' })])[0].severity).toBe('critical');
    expect(transformAlerts([apiAlert({ severity: 'warning' })])[0].severity).toBe('high');
    expect(transformAlerts([apiAlert({ severity: 'info' })])[0].severity).toBe('medium');
  });

  it('derives the title from the message up to the first colon, with an Alert fallback', () => {
    expect(transformAlerts([apiAlert({ message: 'DB: connection lost' })])[0].title).toBe('DB');
    expect(transformAlerts([apiAlert({ message: 'no colon here' })])[0].title).toBe('no colon here');
    expect(transformAlerts([apiAlert({ message: '' })])[0].title).toBe('Alert');
  });

  it('maps pass-through fields and nulls out the ack/resolve audit fields', () => {
    const out = transformAlerts([
      apiAlert({ id: 'x9', component: 'api', message: 'X', acknowledged: true, resolved: true, timestamp: '2024-05-01T10:00:00.000Z' }),
    ])[0];
    expect(out.id).toBe('x9');
    expect(out.component).toBe('api');
    expect(out.message).toBe('X');
    expect(out.acknowledged).toBe(true);
    expect(out.resolved).toBe(true);
    expect(out.created_at).toBe('2024-05-01T10:00:00.000Z');
    expect(out.acknowledged_at).toBeNull();
    expect(out.resolved_by).toBeNull();
    expect(out.metadata).toEqual({});
  });

  it('returns an empty array for no alerts', () => {
    expect(transformAlerts([])).toEqual([]);
  });
});
