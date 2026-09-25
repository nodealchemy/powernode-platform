import { transformAlerts } from './monitoringTransformers';
import type { Alert as ApiAlert } from '@/shared/services/ai/MonitoringApiService';

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
