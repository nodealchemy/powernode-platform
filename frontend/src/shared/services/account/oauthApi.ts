import { apiClient } from '@/shared/services/apiClient';

export interface OAuthApplicationSummary {
  name?: string;
}

export type OAuthAuthorizeParams = Partial<
  Record<
    'client_id' | 'redirect_uri' | 'response_type' | 'scope' | 'state' | 'code_challenge' | 'code_challenge_method',
    string
  >
>;

// The /oauth endpoint family: the consent screen's application lookup and
// the authorization grant (Doorkeeper).
export const oauthApi = {
  async lookupApplication(uid: string): Promise<OAuthApplicationSummary | null> {
    const response = await apiClient.get('/oauth/applications/lookup', { params: { uid } });
    return response.data?.data ?? null;
  },

  /**
   * Grants the authorization. Resolves to the client's redirect URI (carrying
   * the auth code), which Doorkeeper returns in the body or the Location
   * header. A refusal rejects with the axios error, whose body may itself carry
   * a redirect_uri for the error redirect.
   */
  async authorize(params: OAuthAuthorizeParams): Promise<string | undefined> {
    const response = await apiClient.post('/oauth/authorize', params);
    return response.data?.redirect_uri || response.headers?.location;
  },
};
