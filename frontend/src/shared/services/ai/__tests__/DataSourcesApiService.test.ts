import { dataSourcesApi } from '../DataSourcesApiService';

/**
 * x-com-provider campaign (I5): routing coverage for the new OAuth2 authorize
 * call the frontend connect panel depends on.
 */

// `get`/`post` are protected on BaseApiService; expose them for spying.
type SpyablePost = { post: (url: string, body?: unknown) => Promise<unknown> };
const target = dataSourcesApi as unknown as SpyablePost;

describe('DataSourcesApiService#authorizeOauth', () => {
  let postSpy: jest.SpyInstance;

  beforeEach(() => {
    postSpy = jest.spyOn(target, 'post').mockResolvedValue({
      authorization_url: 'https://provider.example.com/authorize',
      redirect_uri: 'https://app.example.com/api/v1/ai/data_sources/ds-1/oauth/callback',
      state: 'state-abc',
    });
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('POSTs to the data source oauth/authorize action', async () => {
    await dataSourcesApi.authorizeOauth('ds-1');

    expect(postSpy).toHaveBeenCalledWith('/ai/data_sources/ds-1/oauth/authorize', undefined);
  });

  it('forwards an explicit credential_id when given', async () => {
    await dataSourcesApi.authorizeOauth('ds-1', 'cred-1');

    expect(postSpy).toHaveBeenCalledWith('/ai/data_sources/ds-1/oauth/authorize', { credential_id: 'cred-1' });
  });

  it('returns the authorization_url/redirect_uri/state envelope', async () => {
    const result = await dataSourcesApi.authorizeOauth('ds-1');

    expect(result).toEqual({
      authorization_url: 'https://provider.example.com/authorize',
      redirect_uri: 'https://app.example.com/api/v1/ai/data_sources/ds-1/oauth/callback',
      state: 'state-abc',
    });
  });
});
