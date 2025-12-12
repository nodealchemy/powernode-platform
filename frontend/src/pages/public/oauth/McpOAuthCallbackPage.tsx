import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { CheckCircle, XCircle, Loader2, Server } from 'lucide-react';
import { mcpApi } from '@/shared/services/ai/McpApiService';

interface CallbackResult {
  success: boolean;
  serverName?: string;
  serverId?: string;
  error?: string;
}

export const McpOAuthCallbackPage: React.FC = () => {
  const [searchParams] = useSearchParams();
  const [result, setResult] = useState<CallbackResult | null>(null);
  const [processing, setProcessing] = useState(true);

  useEffect(() => {
    processCallback();
  }, []);

  const processCallback = async () => {
    const code = searchParams.get('code');
    const state = searchParams.get('state');
    const error = searchParams.get('error');
    const errorDescription = searchParams.get('error_description');

    // Handle OAuth error from provider
    if (error) {
      const errorMessage = errorDescription || error;
      setResult({ success: false, error: errorMessage });
      setProcessing(false);
      notifyOpener(false, undefined, errorMessage);
      return;
    }

    // Validate required parameters
    if (!code || !state) {
      const errorMessage = 'Missing required OAuth parameters';
      setResult({ success: false, error: errorMessage });
      setProcessing(false);
      notifyOpener(false, undefined, errorMessage);
      return;
    }

    try {
      // Exchange code for tokens via backend API
      const response = await mcpApi.completeOAuthCallback({
        code,
        state,
        redirect_uri: window.location.origin + '/oauth/mcp/callback'
      });

      setResult({
        success: true,
        serverId: response.mcp_server_id,
        serverName: response.mcp_server_name
      });
      setProcessing(false);

      // Notify opener window of success
      notifyOpener(true, response.mcp_server_name);

      // Auto-close popup after short delay
      setTimeout(() => {
        window.close();
      }, 2000);
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'OAuth callback failed';
      setResult({ success: false, error: errorMessage });
      setProcessing(false);
      notifyOpener(false, undefined, errorMessage);
    }
  };

  const notifyOpener = (success: boolean, serverName?: string, error?: string) => {
    // Send message to opener window
    if (window.opener) {
      window.opener.postMessage(
        {
          type: 'MCP_OAUTH_CALLBACK',
          success,
          serverName,
          error
        },
        window.location.origin
      );
    }
  };

  const handleClose = () => {
    window.close();
  };

  return (
    <div className="min-h-screen bg-theme-surface flex items-center justify-center p-4">
      <div className="max-w-md w-full bg-theme-surface border border-theme rounded-lg shadow-lg p-8">
        {/* Header */}
        <div className="flex items-center justify-center mb-6">
          <div className="w-12 h-12 bg-theme-info/10 rounded-full flex items-center justify-center">
            <Server className="h-6 w-6 text-theme-info" />
          </div>
        </div>

        <h1 className="text-xl font-semibold text-theme-primary text-center mb-2">
          MCP OAuth Authentication
        </h1>

        {/* Processing State */}
        {processing && (
          <div className="text-center">
            <Loader2 className="h-8 w-8 animate-spin text-theme-info mx-auto mb-4" />
            <p className="text-theme-secondary">
              Completing authentication...
            </p>
          </div>
        )}

        {/* Success State */}
        {!processing && result?.success && (
          <div className="text-center">
            <div className="w-16 h-16 bg-theme-success/10 rounded-full flex items-center justify-center mx-auto mb-4">
              <CheckCircle className="h-8 w-8 text-theme-success" />
            </div>
            <h2 className="text-lg font-medium text-theme-primary mb-2">
              Authentication Successful
            </h2>
            <p className="text-theme-secondary mb-4">
              {result.serverName ? (
                <>Successfully connected to <span className="font-medium">{result.serverName}</span></>
              ) : (
                'OAuth authentication completed'
              )}
            </p>
            <p className="text-sm text-theme-tertiary">
              This window will close automatically...
            </p>
            <button
              onClick={handleClose}
              className="mt-4 text-sm text-theme-info hover:underline"
            >
              Close now
            </button>
          </div>
        )}

        {/* Error State */}
        {!processing && result && !result.success && (
          <div className="text-center">
            <div className="w-16 h-16 bg-theme-error/10 rounded-full flex items-center justify-center mx-auto mb-4">
              <XCircle className="h-8 w-8 text-theme-error" />
            </div>
            <h2 className="text-lg font-medium text-theme-primary mb-2">
              Authentication Failed
            </h2>
            <p className="text-theme-error mb-4">
              {result.error || 'An unknown error occurred'}
            </p>
            <button
              onClick={handleClose}
              className="px-4 py-2 bg-theme-surface border border-theme rounded-md text-theme-primary hover:bg-theme-hover transition-colors"
            >
              Close Window
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default McpOAuthCallbackPage;
