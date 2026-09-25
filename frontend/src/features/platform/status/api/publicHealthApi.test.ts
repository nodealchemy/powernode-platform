import { apiClient } from '@/shared/services/apiClient';
import { publicHealthApi } from './publicHealthApi';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: jest.fn() },
}));

const mockGet = apiClient.get as jest.Mock;

describe('publicHealthApi.check', () => {
  beforeEach(() => mockGet.mockReset());

  it('resolves when /health answers', async () => {
    mockGet.mockResolvedValue({ data: { status: 'ok' } });

    await expect(publicHealthApi.check()).resolves.toBeUndefined();
    expect(mockGet).toHaveBeenCalledWith('/health');
  });

  it('rejects when /health fails', async () => {
    mockGet.mockRejectedValue(new Error('503'));

    await expect(publicHealthApi.check()).rejects.toThrow('503');
  });
});
