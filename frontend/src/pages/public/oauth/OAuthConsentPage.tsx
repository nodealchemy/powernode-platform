import { useEffect, useState } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { isAxiosError } from 'axios';
import { Shield, CheckCircle, XCircle, Loader2 } from 'lucide-react';
import { useAuth } from '@/shared/hooks/useAuth';
import { apiClient } from '@/shared/services/apiClient';

interface ClientInfo {
  name: string;
  scopes: string[];
}

export const OAuthConsentPage: React.FC = () => {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { currentUser, isAuthenticated, isLoading: authLoading } = useAuth();

  const [clientInfo, setClientInfo] = useState<ClientInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const clientId = searchParams.get('client_id');
  const redirectUri = searchParams.get('redirect_uri');
  const scope = searchParams.get('scope') || 'read';
  const responseType = searchParams.get('response_type');
  const state = searchParams.get('state');
  const codeChallenge = searchParams.get('code_challenge');
  const codeChallengeMethod = searchParams.get('code_challenge_method');

  useEffect(() => {
    if (authLoading) return;

    if (!isAuthenticated) {
      const returnUrl = `/app/oauth/authorize?${searchParams.toString()}`;
      navigate('/login', { state: { from: returnUrl } });
      return;
    }

    fetchClientInfo();
  }, [authLoading, isAuthenticated]);

  const fetchClientInfo = async () => {
    if (!clientId) {
      setError('Missing client_id parameter');
      setLoading(false);
      return;
    }

    try {
      const response = await apiClient.get(`/oauth/applications/lookup?uid=${clientId}`);
      const appData = response.data?.data;
      setClientInfo({
        name: appData?.name || 'Unknown Application',
        scopes: scope.split(' ').filter(Boolean),
      });
    } catch {
      // Fall back to showing client_id if lookup fails
      setClientInfo({
        name: clientId,
        scopes: scope.split(' ').filter(Boolean),
      });
    } finally {
      setLoading(false);
    }
  };

  const handleApprove = async () => {
    setSubmitting(true);
    setError(null);

    try {
      const params: Record<string, string> = {};
      if (clientId) params.client_id = clientId;
      if (redirectUri) params.redirect_uri = redirectUri;
      if (responseType) params.response_type = responseType;
      if (scope) params.scope = scope;
      if (state) params.state = state;
      if (codeChallenge) params.code_challenge = codeChallenge;
      if (codeChallengeMethod) params.code_challenge_method = codeChallengeMethod;

      const response = await apiClient.post('/oauth/authorize', params);

      // Doorkeeper returns redirect_uri with auth code
      const redirectTo = response.data?.redirect_uri || response.headers?.location;
      if (redirectTo) {
        window.location.href = redirectTo;
      }
    } catch (err: unknown) {
      if (isAxiosError(err) && err.response?.data) {
        const data = err.response.data;
        if (data.redirect_uri) {
          window.location.href = data.redirect_uri;
          return;
        }
        setError(data.error_description || data.error || 'Authorization failed');
      } else {
        setError(err instanceof Error ? err.message : 'Authorization failed');
      }
      setSubmitting(false);
    }
  };

  const handleDeny = () => {
    if (redirectUri) {
      const separator = redirectUri.includes('?') ? '&' : '?';
      const params = new URLSearchParams({ error: 'access_denied' });
      if (state) params.set('state', state);
      window.location.href = `${redirectUri}${separator}${params.toString()}`;
    } else {
      navigate('/app');
    }
  };

  const scopeDescriptions: Record<string, string> = {
    read: 'Read access to your data',
    write: 'Create and modify data',
    workflows: 'Access AI workflows and automation',
    files: 'Access file management',
  };

  if (authLoading || loading) {
    return (
      <div className="min-h-screen bg-theme-surface flex items-center justify-center p-4">
        <div className="max-w-md w-full bg-theme-surface border border-theme rounded-lg shadow-lg p-8 text-center">
          <Loader2 className="h-8 w-8 animate-spin text-theme-info mx-auto mb-4" />
          <p className="text-theme-secondary">Loading authorization request...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-theme-surface flex items-center justify-center p-4">
      <div className="max-w-md w-full bg-theme-surface border border-theme rounded-lg shadow-lg p-8">
        {/* Header */}
        <div className="flex items-center justify-center mb-6">
          <div className="w-12 h-12 bg-theme-info/10 rounded-full flex items-center justify-center">
            <Shield className="h-6 w-6 text-theme-info" />
          </div>
        </div>

        <h1 className="text-xl font-semibold text-theme-primary text-center mb-2">
          Authorization Request
        </h1>

        <p className="text-theme-secondary text-center mb-6">
          <span className="font-medium text-theme-primary">{clientInfo?.name}</span>
          {' '}wants to access your account
        </p>

        {/* Signed in as */}
        <div className="bg-theme-hover/50 rounded-md p-3 mb-6">
          <p className="text-sm text-theme-secondary">
            Signed in as <span className="font-medium text-theme-primary">{currentUser?.email}</span>
          </p>
        </div>

        {/* Requested permissions */}
        <div className="mb-6">
          <h2 className="text-sm font-medium text-theme-secondary mb-3">This will allow the application to:</h2>
          <ul className="space-y-2">
            {clientInfo?.scopes.map((s) => (
              <li key={s} className="flex items-start gap-2">
                <CheckCircle className="h-4 w-4 text-theme-success mt-0.5 flex-shrink-0" />
                <span className="text-sm text-theme-primary">
                  {scopeDescriptions[s] || s}
                </span>
              </li>
            ))}
          </ul>
        </div>

        {/* Error */}
        {error && (
          <div className="flex items-center gap-2 p-3 mb-4 bg-theme-error/10 border border-theme-error/20 rounded-md">
            <XCircle className="h-4 w-4 text-theme-error flex-shrink-0" />
            <p className="text-sm text-theme-error">{error}</p>
          </div>
        )}

        {/* Actions */}
        <div className="flex gap-3">
          <button
            onClick={handleDeny}
            disabled={submitting}
            className="flex-1 px-4 py-2 bg-theme-surface border border-theme rounded-md text-theme-primary hover:bg-theme-hover transition-colors disabled:opacity-50"
          >
            Deny
          </button>
          <button
            onClick={handleApprove}
            disabled={submitting}
            className="flex-1 px-4 py-2 bg-theme-info text-white rounded-md hover:bg-theme-info/90 transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
          >
            {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
            Approve
          </button>
        </div>
      </div>
    </div>
  );
};

export default OAuthConsentPage;
