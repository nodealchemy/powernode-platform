import { roiApi } from '../RoiApiService';

/**
 * Regression guard for the ROI 404 fix: the RoiCalculationsController endpoints
 * live under the `roi/calculations` backend scope, while the base RoiController
 * endpoints live under `roi`. The frontend service had drifted, calling the
 * calculation endpoints at `/ai/roi/*` (→ 404). These tests assert the split.
 */

// `get`/`post` are protected on BaseApiService; expose them for spying.
type SpyableRoi = {
  get: (url: string, config?: unknown) => Promise<unknown>;
  post: (url: string, body?: unknown) => Promise<unknown>;
};
const target = roiApi as unknown as SpyableRoi;

describe('RoiApiService endpoint routing', () => {
  let getSpy: jest.SpyInstance;
  let postSpy: jest.SpyInstance;

  beforeEach(() => {
    getSpy = jest.spyOn(target, 'get').mockResolvedValue({});
    postSpy = jest.spyOn(target, 'post').mockResolvedValue({});
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('routes calculation reads under /ai/roi/calculations', async () => {
    await roiApi.getMetrics();
    await roiApi.getMetric('abc');
    await roiApi.getProjections();
    await roiApi.getRecommendations();
    await roiApi.compare();

    const paths = getSpy.mock.calls.map((c) => c[0] as string);
    expect(paths).toContain('/ai/roi/calculations/metrics');
    expect(paths).toContain('/ai/roi/calculations/metrics/abc');
    expect(paths).toContain('/ai/roi/calculations/projections');
    expect(paths).toContain('/ai/roi/calculations/recommendations');
    expect(paths).toContain('/ai/roi/calculations/compare');
  });

  it('routes calculation writes (calculate/aggregate) under /ai/roi/calculations', async () => {
    await roiApi.calculate({ date: '2026-01-01' });
    await roiApi.aggregate('daily', '2026-01-01');

    const paths = postSpy.mock.calls.map((c) => c[0] as string);
    expect(paths).toContain('/ai/roi/calculations/calculate');
    expect(paths).toContain('/ai/roi/calculations/aggregate');
  });

  it('keeps base ROI reads on /ai/roi (never /calculations)', async () => {
    await roiApi.getDashboard();
    await roiApi.getSummary();
    await roiApi.getTrends();
    await roiApi.getByAgent();
    await roiApi.getCostBreakdown();
    await roiApi.getAttributions();

    const paths = getSpy.mock.calls.map((c) => c[0] as string);
    expect(paths.every((p) => !p.includes('/calculations'))).toBe(true);
    expect(paths.some((p) => p.startsWith('/ai/roi/dashboard'))).toBe(true);
  });
});
