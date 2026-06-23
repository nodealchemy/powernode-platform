import { contextApi } from './contextApi';
import { api } from '@/shared/services/api';
import { createMockAxiosResponse } from '@/shared/utils/test-utils';

// Regression: getEntries/getAgentMemory used `if (filters?.min_importance)` — a truthy
// check that drops a legitimate 0, so the param was never sent and the backend applied a
// different default. (has_embedding in the same function correctly uses `!== undefined`.)
jest.mock('@/shared/services/api', () => ({
  api: { get: jest.fn(), post: jest.fn(), put: jest.fn(), delete: jest.fn() },
}));

const mockApi = jest.mocked(api);

describe('contextApi min_importance filter', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockApi.get.mockResolvedValue(createMockAxiosResponse({ success: true }));
  });

  it('getEntries forwards min_importance when it is 0', async () => {
    await contextApi.getEntries('ctx-1', 1, 20, { min_importance: 0 });
    const url = mockApi.get.mock.calls[0][0] as string;
    expect(url).toContain('min_importance=0');
  });

  it('getEntries omits min_importance when not provided', async () => {
    await contextApi.getEntries('ctx-1', 1, 20, {});
    const url = mockApi.get.mock.calls[0][0] as string;
    expect(url).not.toContain('min_importance');
  });

  it('getAgentMemory forwards min_importance when it is 0', async () => {
    await contextApi.getAgentMemory('agent-1', 1, 20, { min_importance: 0 });
    const url = mockApi.get.mock.calls[0][0] as string;
    expect(url).toContain('min_importance=0');
  });
});
