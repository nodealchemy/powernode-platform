import React, { useEffect, useState, useCallback } from 'react';
import { Copy, ExternalLink, RefreshCw, AlertTriangle } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Badge } from '@/shared/components/ui/Badge';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import type { AiDataSource, AiDataSourceCredential, DataSourceOauthAuthorizeResponse } from '@/shared/types/ai';

interface DataSourceOauthConnectPanelProps {
  dataSource: AiDataSource;
  canManage: boolean;
  onCredentialsChanged: () => void;
}

// Browser navigation, factored out as a mutable object rather than a bare
// `window.location.assign` call so tests can `jest.spyOn` it — jsdom locks
// down `window.location` and its methods as non-configurable, so it can't be
// stubbed directly.
export const oauthConnectPanelNav = {
  navigate: (url: string) => {
    window.location.assign(url);
  },
};

/**
 * x-com-provider campaign (I5) — OAuth2 Authorization Code + PKCE connect UX.
 * Provider-agnostic: shown for ANY data source whose auth_config.authorize_url
 * is configured (not just X.com), matching the backend service's framing.
 *
 * Flow: save the OAuth app's client_id/client_secret as a credential -> fetch
 * the redirect_uri to register on the provider's app config -> click "Authorize"
 * to navigate the browser to the provider. The backend callback redirects back
 * here with ?oauth=success|failed, handled by useDataSourcesPage.
 */
export const DataSourceOauthConnectPanel: React.FC<DataSourceOauthConnectPanelProps> = ({
  dataSource,
  canManage,
  onCredentialsChanged,
}) => {
  const { addNotification } = useNotifications();

  // The credential holding (or about to hold) the OAuth app's client_id/secret —
  // the default one if set, else the first credential, else none yet.
  const oauthCredential: AiDataSourceCredential | undefined =
    dataSource.credentials?.find((c) => c.oauth_configured) ||
    dataSource.credentials?.find((c) => c.is_default) ||
    dataSource.credentials?.[0];

  const [clientId, setClientId] = useState('');
  const [clientSecret, setClientSecret] = useState('');
  const [savingCredential, setSavingCredential] = useState(false);
  const [showAppForm, setShowAppForm] = useState(!oauthCredential?.oauth_configured);

  const [authorizeInfo, setAuthorizeInfo] = useState<DataSourceOauthAuthorizeResponse | null>(null);
  const [loadingAuthorize, setLoadingAuthorize] = useState(false);

  const supportsOauth = Boolean(dataSource.auth_config?.authorize_url);

  const fetchAuthorizeInfo = useCallback(async () => {
    if (!oauthCredential?.oauth_configured) return;
    try {
      setLoadingAuthorize(true);
      const info = await dataSourcesApi.authorizeOauth(dataSource.id, oauthCredential.id);
      setAuthorizeInfo(info);
    } catch (_error) {
      addNotification({ type: 'error', title: 'OAuth Setup', message: 'Failed to prepare the OAuth connection.' });
    } finally {
      setLoadingAuthorize(false);
    }
  }, [dataSource.id, oauthCredential?.id, oauthCredential?.oauth_configured, addNotification]);

  useEffect(() => {
    if (supportsOauth && oauthCredential?.oauth_configured) {
      fetchAuthorizeInfo();
    }
    // Only re-fetch when the underlying credential identity/config changes, not
    // on every render (fetchAuthorizeInfo mints a new short-lived server state).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [supportsOauth, oauthCredential?.id, oauthCredential?.oauth_configured]);

  if (!supportsOauth) return null;

  const handleCopyRedirectUri = () => {
    if (!authorizeInfo?.redirect_uri) return;
    navigator.clipboard.writeText(authorizeInfo.redirect_uri);
    addNotification({ type: 'success', title: 'Copied', message: 'Redirect URI copied to clipboard' });
  };

  const handleSaveAppCredentials = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!clientId.trim()) {
      addNotification({ type: 'error', title: 'OAuth Setup', message: 'Client ID is required' });
      return;
    }

    setSavingCredential(true);
    try {
      const payload = {
        client_id: clientId.trim(),
        ...(clientSecret.trim() ? { client_secret: clientSecret.trim() } : {}),
      };

      if (oauthCredential) {
        await dataSourcesApi.updateCredential(dataSource.id, oauthCredential.id, payload);
      } else {
        await dataSourcesApi.createCredential(dataSource.id, {
          name: `${dataSource.name} OAuth App`,
          is_active: true,
          ...payload,
        });
      }

      addNotification({ type: 'success', title: 'OAuth App Saved', message: 'App credentials saved successfully' });
      setClientId('');
      setClientSecret('');
      setShowAppForm(false);
      onCredentialsChanged();
    } catch (_error) {
      addNotification({ type: 'error', title: 'Save Failed', message: 'Failed to save the app credentials' });
    } finally {
      setSavingCredential(false);
    }
  };

  const handleAuthorize = () => {
    if (!authorizeInfo?.authorization_url) return;
    oauthConnectPanelNav.navigate(authorizeInfo.authorization_url);
  };

  const formatExpiry = (iso?: string | null) => {
    if (!iso) return null;
    return new Date(iso).toLocaleString();
  };

  return (
    <Card>
      <CardHeader title="OAuth2 Connection" />
      <CardContent className="space-y-4">
        {oauthCredential?.oauth_connected ? (
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="success" size="sm">Connected</Badge>
            {oauthCredential.oauth_token_expired && (
              <Badge variant="warning" size="sm">
                <span className="flex items-center gap-1"><AlertTriangle className="h-3 w-3" /> Token expired</span>
              </Badge>
            )}
            {(oauthCredential.oauth_scopes || []).map((scope) => (
              <Badge key={scope} variant="outline" size="sm">{scope}</Badge>
            ))}
            {oauthCredential.oauth_token_expires_at && (
              <span className="text-xs text-theme-tertiary">
                Token expires: {formatExpiry(oauthCredential.oauth_token_expires_at)}
              </span>
            )}
          </div>
        ) : (
          <Badge variant="secondary" size="sm">Not connected</Badge>
        )}

        {canManage && (showAppForm || !oauthCredential?.oauth_configured) && (
          <form onSubmit={handleSaveAppCredentials} className="space-y-3 p-4 border border-dashed border-theme rounded-lg">
            <p className="text-xs text-theme-tertiary">
              Enter the OAuth app credentials registered with the provider. The secret is never
              displayed again once saved — leave it blank on a later edit to keep the existing one.
            </p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <Input
                label="Client ID"
                value={clientId}
                onChange={(e) => setClientId(e.target.value)}
                placeholder="OAuth app client ID"
                autoComplete="new-password"
                required
              />
              <Input
                label="Client Secret"
                type="password"
                value={clientSecret}
                onChange={(e) => setClientSecret(e.target.value)}
                placeholder={oauthCredential?.oauth_configured ? 'Leave blank to keep existing' : 'OAuth app client secret'}
                autoComplete="new-password"
              />
            </div>
            <div className="flex justify-end">
              <Button type="submit" size="sm" disabled={savingCredential}>
                {savingCredential ? 'Saving...' : 'Save App Credentials'}
              </Button>
            </div>
          </form>
        )}

        {oauthCredential?.oauth_configured && (
          <div className="space-y-3">
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">
                Redirect URI (register this with the provider)
              </label>
              <div className="flex items-center gap-2">
                <Input
                  readOnly
                  value={authorizeInfo?.redirect_uri || ''}
                  placeholder={loadingAuthorize ? 'Loading...' : ''}
                  className="font-mono text-xs"
                />
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={handleCopyRedirectUri}
                  disabled={!authorizeInfo?.redirect_uri}
                  title="Copy redirect URI"
                >
                  <Copy className="h-4 w-4" />
                </Button>
              </div>
            </div>

            {canManage && (
              <div className="flex flex-wrap items-center gap-2">
                <Button
                  type="button"
                  onClick={handleAuthorize}
                  disabled={loadingAuthorize || !authorizeInfo?.authorization_url}
                  className="flex items-center gap-2"
                >
                  <ExternalLink className="h-4 w-4" />
                  {oauthCredential.oauth_connected ? 'Reconnect' : 'Authorize'} with the Provider
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={fetchAuthorizeInfo}
                  disabled={loadingAuthorize}
                  title="Refresh the redirect URI / authorization link"
                >
                  <RefreshCw className={`h-4 w-4 ${loadingAuthorize ? 'animate-spin' : ''}`} />
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => setShowAppForm((prev) => !prev)}
                >
                  {showAppForm ? 'Hide' : 'Edit'} App Credentials
                </Button>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
};
