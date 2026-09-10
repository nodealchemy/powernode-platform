import { monitoringApi } from '../MonitoringApiService';
import type { StatusRollup } from '@/shared/types/platformStatus';

/**
 * component-status-plane campaign (E7 fallout): `getDashboard()`'s
 * `system_health.uptime_percentage` used to read a `health_score` field the
 * `/dashboard` endpoint never actually nested under `dashboard` (it was a
 * sibling of it, pre-E7), so `dashboard?.health_score || 100` silently
 * reported "100% uptime" on every call. It now derives a genuine percentage
 * from the `rollup` sibling `platform_rollup` returns.
 *
 * `get` is protected on BaseApiService; expose it for spying.
 */
type SpyableGet = { get: (url: string, config?: unknown) => Promise<unknown> };
const target = monitoringApi as unknown as SpyableGet;

const rollup = (overrides: Partial<StatusRollup> = {}): StatusRollup => ({
  verdict: 'ok',
  held_count: 0,
  counts_by_verdict: { ok: 0, held: 0, progressing: 0, not_measured: 0, degraded: 0, down: 0 },
  total: 0,
  ...overrides,
});

describe('MonitoringApiService#getDashboard — uptime_percentage derivation', () => {
  let getSpy: jest.SpyInstance;

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('derives 100% when every tracked component is healthy', async () => {
    getSpy = jest.spyOn(target, 'get').mockResolvedValue({
      dashboard: {},
      rollup: rollup({ verdict: 'ok', total: 4, counts_by_verdict: { ok: 4, held: 0, progressing: 0, not_measured: 0, degraded: 0, down: 0 } }),
    });

    const result = await monitoringApi.getDashboard();

    expect(result.system_health.uptime_percentage).toBe(100);
  });

  it('derives a genuine partial percentage from degraded/down/not_measured counts — NOT a fabricated 100', async () => {
    getSpy = jest.spyOn(target, 'get').mockResolvedValue({
      dashboard: {},
      // 10 total, 3 unhealthy (1 degraded, 1 down, 1 not_measured) -> 70%.
      rollup: rollup({
        verdict: 'down',
        total: 10,
        counts_by_verdict: { ok: 6, held: 1, progressing: 0, not_measured: 1, degraded: 1, down: 1 },
      }),
    });

    const result = await monitoringApi.getDashboard();

    expect(result.system_health.uptime_percentage).toBe(70);
  });

  it('derives 0% — NOT 100% — when every tracked component is down (proves no `|| 100` coercion on a falsy-but-real 0)', async () => {
    getSpy = jest.spyOn(target, 'get').mockResolvedValue({
      dashboard: {},
      rollup: rollup({ verdict: 'down', total: 2, counts_by_verdict: { ok: 0, held: 0, progressing: 0, not_measured: 0, degraded: 0, down: 2 } }),
    });

    const result = await monitoringApi.getDashboard();

    expect(result.system_health.uptime_percentage).toBe(0);
  });

  it('falls back to 100 only when total is genuinely zero (a real vacuous answer, not a hidden-signal guess)', async () => {
    getSpy = jest.spyOn(target, 'get').mockResolvedValue({
      dashboard: {},
      rollup: rollup({ verdict: 'ok', total: 0 }),
    });

    const result = await monitoringApi.getDashboard();

    expect(result.system_health.uptime_percentage).toBe(100);
  });

  it('falls back to 100 when rollup is entirely absent from the payload (defensive, not the removed-signal path)', async () => {
    getSpy = jest.spyOn(target, 'get').mockResolvedValue({ dashboard: {} });

    const result = await monitoringApi.getDashboard();

    expect(result.system_health.uptime_percentage).toBe(100);
    expect(getSpy).toHaveBeenCalled();
  });
});
