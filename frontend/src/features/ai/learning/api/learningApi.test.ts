import { apiClient } from '@/shared/services/apiClient';
import { learningApi } from './learningApi';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: jest.fn(), post: jest.fn() },
}));

const mockGet = apiClient.get as jest.Mock;
const mockPost = apiClient.post as jest.Mock;

// Every fixture below is the REAL server envelope ({ success, data: {...} },
// plus a top-level meta where render_success passes meta:) as axios hands it
// back in response.data. The client unwraps it; callers never see .data.data.
const envelope = (data: unknown, meta?: unknown) => ({
  data: meta ? { success: true, data, meta } : { success: true, data },
});

describe('learningApi (one client for /ai/learning)', () => {
  beforeEach(() => {
    mockGet.mockReset();
    mockPost.mockReset();
  });

  it('lists recommendations from /ai/learning/recommendations', async () => {
    mockGet.mockResolvedValue(envelope({ recommendations: [{ id: 'r1' }] }));

    await expect(learningApi.getRecommendations()).resolves.toEqual([{ id: 'r1' }]);
    expect(mockGet).toHaveBeenCalledWith('/ai/learning/recommendations');
  });

  it('applies and dismisses a recommendation by id', async () => {
    mockPost.mockResolvedValue(envelope({ recommendation: { id: 'r1', status: 'applied' } }));

    await expect(learningApi.applyRecommendation('r1')).resolves.toEqual({ id: 'r1', status: 'applied' });
    expect(mockPost).toHaveBeenCalledWith('/ai/learning/recommendations/r1/apply');

    mockPost.mockResolvedValue(envelope({ recommendation: { id: 'r1', status: 'dismissed' } }));
    await expect(learningApi.dismissRecommendation('r1')).resolves.toEqual({ id: 'r1', status: 'dismissed' });
    expect(mockPost).toHaveBeenCalledWith('/ai/learning/recommendations/r1/dismiss');
  });

  it('reads agent trends and cache metrics', async () => {
    mockGet.mockResolvedValueOnce(envelope({ trends: [{ agent_id: 'a1' }] }));
    await expect(learningApi.getAgentTrends()).resolves.toEqual([{ agent_id: 'a1' }]);
    expect(mockGet).toHaveBeenLastCalledWith('/ai/learning/agent_trends');

    mockGet.mockResolvedValueOnce(envelope({ metrics: { hits: 3, misses: 1, hit_rate: 75, estimated_savings_usd: 0.1 } }));
    await expect(learningApi.getCacheMetrics()).resolves.toEqual({
      hits: 3,
      misses: 1,
      hit_rate: 75,
      estimated_savings_usd: 0.1,
    });
    expect(mockGet).toHaveBeenLastCalledWith('/ai/learning/cache_metrics');
  });

  it('returns null cache metrics when the server sends none', async () => {
    mockGet.mockResolvedValue({ data: { success: true } });
    await expect(learningApi.getCacheMetrics()).resolves.toBeNull();
  });

  it('reads compound metrics', async () => {
    mockGet.mockResolvedValue(envelope({ metrics: { total_learnings: 4 } }));
    await expect(learningApi.getCompoundMetrics()).resolves.toEqual({ total_learnings: 4 });
    expect(mockGet).toHaveBeenCalledWith('/ai/learning/compound_metrics');
  });

  it('lists learnings with filters, taking meta from the top-level envelope', async () => {
    mockGet.mockResolvedValue(
      envelope({ learnings: [{ id: 'l1' }] }, { total_count: 9, offset: 0, limit: 5 })
    );

    const page = await learningApi.getLearnings({ status: 'active', limit: 5, sort_by: 'importance_score' });

    expect(mockGet).toHaveBeenCalledWith(
      '/ai/learning/learnings?status=active&limit=5&sort_by=importance_score'
    );
    expect(page).toEqual({ learnings: [{ id: 'l1' }], meta: { total_count: 9, offset: 0, limit: 5 } });
  });

  it('reinforces a learning and promotes cross-team', async () => {
    mockPost.mockResolvedValueOnce(envelope({ learning: { id: 'l1' } }));
    await expect(learningApi.reinforceLearning('l1')).resolves.toEqual({ id: 'l1' });
    expect(mockPost).toHaveBeenLastCalledWith('/ai/learning/reinforce/l1');

    mockPost.mockResolvedValueOnce(envelope({ promoted_count: 2 }));
    await expect(learningApi.promoteCrossTeam()).resolves.toBe(2);
    expect(mockPost).toHaveBeenLastCalledWith('/ai/learning/promote');
  });

  it('reads evaluation results and benchmarks with params', async () => {
    mockGet.mockResolvedValueOnce(envelope({ results: [{ id: 'e1' }] }));
    await expect(learningApi.getEvaluationResults({ agent_id: 'a1', limit: 10 })).resolves.toEqual([{ id: 'e1' }]);
    expect(mockGet).toHaveBeenLastCalledWith('/ai/learning/evaluation_results', {
      params: { agent_id: 'a1', limit: 10 },
    });

    mockGet.mockResolvedValueOnce(envelope({ benchmarks: [{ id: 'b1' }] }));
    await expect(learningApi.getBenchmarks()).resolves.toEqual([{ id: 'b1' }]);
    expect(mockGet).toHaveBeenLastCalledWith('/ai/learning/benchmarks', { params: undefined });
  });

  it('creates and runs a benchmark', async () => {
    mockPost.mockResolvedValueOnce(envelope({ benchmark: { id: 'b1' } }));
    await expect(learningApi.createBenchmark({ name: 'B' })).resolves.toEqual({ id: 'b1' });
    expect(mockPost).toHaveBeenLastCalledWith('/ai/learning/benchmarks', { name: 'B' });

    mockPost.mockResolvedValueOnce(envelope({ benchmark: { id: 'b1' }, results: { score: 1 } }));
    await expect(learningApi.runBenchmark('b1')).resolves.toEqual({ benchmark: { id: 'b1' }, results: { score: 1 } });
    expect(mockPost).toHaveBeenLastCalledWith('/ai/learning/benchmarks/b1/run');
  });
});
