import { apiClient } from '@/shared/services/apiClient';
import { oauthApi } from './oauthApi';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: jest.fn(), post: jest.fn() },
}));

const mockGet = apiClient.get as jest.Mock;
const mockPost = apiClient.post as jest.Mock;

describe('oauthApi', () => {
  beforeEach(() => {
    mockGet.mockReset();
    mockPost.mockReset();
  });

  it('looks up an application by uid and unwraps the envelope', async () => {
    mockGet.mockResolvedValue({ data: { success: true, data: { name: 'CLI' } } });

    await expect(oauthApi.lookupApplication('uid-1')).resolves.toEqual({ name: 'CLI' });
    expect(mockGet).toHaveBeenCalledWith('/oauth/applications/lookup', { params: { uid: 'uid-1' } });
  });

  it('returns the redirect URI from the authorize response body', async () => {
    mockPost.mockResolvedValue({ data: { redirect_uri: 'https://client/cb?code=abc' }, headers: {} });

    await expect(oauthApi.authorize({ client_id: 'uid-1', scope: 'read' })).resolves.toBe('https://client/cb?code=abc');
    expect(mockPost).toHaveBeenCalledWith('/oauth/authorize', { client_id: 'uid-1', scope: 'read' });
  });

  it('falls back to the Location header', async () => {
    mockPost.mockResolvedValue({ data: {}, headers: { location: 'https://client/cb?code=xyz' } });

    await expect(oauthApi.authorize({})).resolves.toBe('https://client/cb?code=xyz');
  });
});
