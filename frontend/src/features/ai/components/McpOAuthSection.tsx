import { useState, useEffect } from 'react';
import {
  Shield,
  CheckCircle,
  XCircle,
  AlertTriangle,
  RefreshCw,
  ExternalLink,
  Clock,
  Loader2,
  Unplug
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { mcpApi, McpServerOAuthStatus } from '@/shared/services/ai/McpApiService';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface McpOAuthSectionProps {
  serverId: string;
  serverName: string;
  authType: 'none' | 'api_key' | 'oauth2';
  onStatusChange?: () => void;
}

export const McpOAuthSection: React.FC<McpOAuthSectionProps> = ({
  serverId,
  serverName,
  authType,
  onStatusChange
}) => {
  const [oauthStatus, setOAuthStatus] = useState<McpServerOAuthStatus | null>(null);
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const { addNotification } = useNotifications();

  useEffect(() => {
    if (authType === 'oauth2') {
      fetchOAuthStatus();
    }
  }, [serverId, authType]);

  const fetchOAuthStatus = async () => {
    try {
      setLoading(true);
      const status = await mcpApi.getOAuthStatus(serverId);
      setOAuthStatus(status);
    } catch (error) {
      // OAuth status endpoint may fail if not configured yet
      setOAuthStatus(null);
    } finally {
      setLoading(false);
    }
  };

  const handleConnect = async () => {
    try {
      setLoading(true);
      const { authorization_url } = await mcpApi.initiateOAuth(serverId);

      // Open OAuth authorization in a new window
      const width = 600;
      const height = 700;
      const left = window.screenX + (window.outerWidth - width) / 2;
      const top = window.screenY + (window.outerHeight - height) / 2;

      const popup = window.open(
        authorization_url,
        'mcp-oauth',
        `width=${width},height=${height},left=${left},top=${top},popup=1`
      );

      // Listen for callback message from popup
      const handleMessage = (event: MessageEvent) => {
        if (event.data?.type === 'MCP_OAUTH_CALLBACK') {
          window.removeEventListener('message', handleMessage);
          if (event.data.success) {
            addNotification({ type: 'success', message: `OAuth connected for ${serverName}` });
            fetchOAuthStatus();
            onStatusChange?.();
          } else {
            addNotification({ type: 'error', message: event.data.error || 'OAuth connection failed' });
          }
          setLoading(false);
        }
      };

      window.addEventListener('message', handleMessage);

      // Monitor if popup is closed without completing
      const checkClosed = setInterval(() => {
        if (popup?.closed) {
          clearInterval(checkClosed);
          window.removeEventListener('message', handleMessage);
          setLoading(false);
        }
      }, 1000);
    } catch (error) {
      addNotification({ type: 'error', message: 'Failed to initiate OAuth flow' });
      setLoading(false);
    }
  };

  const handleDisconnect = async () => {
    try {
      setLoading(true);
      await mcpApi.disconnectOAuth(serverId);
      addNotification({ type: 'success', message: `OAuth disconnected for ${serverName}` });
      fetchOAuthStatus();
      onStatusChange?.();
    } catch (error) {
      addNotification({ type: 'error', message: 'Failed to disconnect OAuth' });
    } finally {
      setLoading(false);
    }
  };

  const handleRefreshToken = async () => {
    try {
      setRefreshing(true);
      await mcpApi.refreshOAuthToken(serverId);
      addNotification({ type: 'success', message: 'OAuth token refreshed' });
      fetchOAuthStatus();
    } catch (error) {
      addNotification({ type: 'error', message: 'Failed to refresh OAuth token' });
    } finally {
      setRefreshing(false);
    }
  };

  if (authType !== 'oauth2') {
    return null;
  }

  const formatExpiresAt = (dateString?: string) => {
    if (!dateString) return 'Unknown';
    const date = new Date(dateString);
    const now = new Date();
    const diff = date.getTime() - now.getTime();

    if (diff < 0) return 'Expired';
    if (diff < 60 * 1000) return 'Less than a minute';
    if (diff < 60 * 60 * 1000) return `${Math.round(diff / (60 * 1000))} minutes`;
    if (diff < 24 * 60 * 60 * 1000) return `${Math.round(diff / (60 * 60 * 1000))} hours`;
    return date.toLocaleDateString();
  };

  return (
    <div className="border border-theme rounded-lg p-4 bg-theme-surface">
      <div className="flex items-center gap-2 mb-4">
        <Shield className="h-5 w-5 text-theme-info" />
        <h3 className="text-sm font-medium text-theme-primary">OAuth 2.1 Authentication</h3>
      </div>

      {loading && !oauthStatus ? (
        <div className="flex items-center justify-center py-4">
          <Loader2 className="h-5 w-5 animate-spin text-theme-info" />
          <span className="ml-2 text-sm text-theme-secondary">Loading OAuth status...</span>
        </div>
      ) : oauthStatus?.oauth_connected ? (
        <div className="space-y-4">
          {/* Connected Status */}
          <div className="flex items-center gap-2 text-theme-success">
            <CheckCircle className="h-4 w-4" />
            <span className="text-sm font-medium">Connected</span>
          </div>

          {/* Token Info */}
          <div className="grid grid-cols-2 gap-4 text-sm">
            {oauthStatus.oauth_provider && (
              <div>
                <span className="text-theme-tertiary">Provider:</span>
                <span className="ml-2 text-theme-primary capitalize">{oauthStatus.oauth_provider}</span>
              </div>
            )}

            <div className="flex items-center gap-1">
              <Clock className="h-3 w-3 text-theme-tertiary" />
              <span className="text-theme-tertiary">Expires:</span>
              <span className={`ml-1 ${oauthStatus.oauth_token_expired ? 'text-theme-error' : 'text-theme-primary'}`}>
                {formatExpiresAt(oauthStatus.oauth_token_expires_at)}
              </span>
            </div>

            {oauthStatus.oauth_scopes && (
              <div className="col-span-2">
                <span className="text-theme-tertiary">Scopes:</span>
                <span className="ml-2 text-theme-primary font-mono text-xs">{oauthStatus.oauth_scopes}</span>
              </div>
            )}
          </div>

          {/* Token Expiry Warning */}
          {oauthStatus.oauth_token_expired && (
            <div className="flex items-center gap-2 p-2 bg-theme-warning/10 rounded text-theme-warning text-sm">
              <AlertTriangle className="h-4 w-4" />
              <span>Token has expired. Refresh to continue using this server.</span>
            </div>
          )}

          {/* Error Display */}
          {oauthStatus.oauth_error && (
            <div className="flex items-center gap-2 p-2 bg-theme-error/10 rounded text-theme-error text-sm">
              <XCircle className="h-4 w-4" />
              <span>{oauthStatus.oauth_error}</span>
            </div>
          )}

          {/* Actions */}
          <div className="flex gap-2 pt-2 border-t border-theme">
            <Button
              variant="outline"
              size="sm"
              onClick={handleRefreshToken}
              disabled={refreshing}
            >
              {refreshing ? (
                <Loader2 className="h-4 w-4 mr-1 animate-spin" />
              ) : (
                <RefreshCw className="h-4 w-4 mr-1" />
              )}
              Refresh Token
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={handleDisconnect}
              disabled={loading}
              className="text-theme-error hover:bg-theme-error/10"
            >
              <Unplug className="h-4 w-4 mr-1" />
              Disconnect
            </Button>
          </div>
        </div>
      ) : oauthStatus?.oauth_configured ? (
        <div className="space-y-4">
          {/* Not Connected Status */}
          <div className="flex items-center gap-2 text-theme-warning">
            <AlertTriangle className="h-4 w-4" />
            <span className="text-sm font-medium">OAuth configured but not connected</span>
          </div>

          {oauthStatus.oauth_error && (
            <div className="flex items-center gap-2 p-2 bg-theme-error/10 rounded text-theme-error text-sm">
              <XCircle className="h-4 w-4" />
              <span>{oauthStatus.oauth_error}</span>
            </div>
          )}

          <Button
            variant="primary"
            size="sm"
            onClick={handleConnect}
            disabled={loading}
          >
            {loading ? (
              <Loader2 className="h-4 w-4 mr-1 animate-spin" />
            ) : (
              <ExternalLink className="h-4 w-4 mr-1" />
            )}
            Connect with OAuth
          </Button>
        </div>
      ) : (
        <div className="space-y-4">
          {/* Not Configured */}
          <div className="flex items-center gap-2 text-theme-tertiary">
            <XCircle className="h-4 w-4" />
            <span className="text-sm">OAuth not configured</span>
          </div>
          <p className="text-xs text-theme-secondary">
            Configure OAuth credentials in the server settings to enable external authentication.
          </p>
        </div>
      )}
    </div>
  );
};

export default McpOAuthSection;
