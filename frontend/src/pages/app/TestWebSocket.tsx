import React, { useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { RefreshCw } from 'lucide-react';

export const TestWebSocket: React.FC = () => {
  const { user, access_token } = useSelector((state: RootState) => state.auth);
  const { isConnected, error, lastConnected } = useWebSocket();
  
  useEffect(() => {
  }, [user, access_token, isConnected, error, lastConnected]);
  
  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app' },
    { label: 'WebSocket Test' }
  ];

  const getPageActions = () => [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: () => window.location.reload(),
      variant: 'secondary' as const,
      icon: RefreshCw
    }
  ];

  return (
    <PageContainer
      title="WebSocket Test"
      description="Test WebSocket connection and authentication"
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="text-sm font-medium text-theme-secondary">User</label>
              <p className="mt-1 text-theme-primary">{user?.email || 'Not logged in'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-theme-secondary">Account ID</label>
              <p className="mt-1 text-theme-primary font-mono text-sm">{user?.account?.id || 'Missing'}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-theme-secondary">Access Token</label>
              <p className="mt-1">
                <span className={`inline-flex px-2 py-1 text-xs font-medium rounded-full ${
                  access_token ? 'bg-theme-success-bg text-theme-success-fg' : 'bg-theme-error-bg text-theme-error-fg'
                }`}>
                  {access_token ? 'Present' : 'Missing'}
                </span>
              </p>
            </div>
            <div>
              <label className="text-sm font-medium text-theme-secondary">Connection Status</label>
              <p className="mt-1">
                <span className={`inline-flex items-center px-2 py-1 text-xs font-medium rounded-full ${
                  isConnected ? 'bg-theme-success-bg text-theme-success-fg' : 'bg-theme-error-bg text-theme-error-fg'
                }`}>
                  <span className={`w-2 h-2 rounded-full mr-1.5 ${
                    isConnected ? 'bg-theme-success-bg' : 'bg-theme-error-bg'
                  }`} />
                  {isConnected ? 'Connected' : 'Disconnected'}
                </span>
              </p>
            </div>
          </div>
          
          {error && (
            <div className="bg-theme-error-bg border border-theme-error-border rounded-lg p-4">
              <h3 className="text-sm font-medium text-theme-error-fg mb-1">Error</h3>
              <p className="text-sm text-theme-error-fg">{error}</p>
            </div>
          )}
          
          {lastConnected && (
            <div className="bg-theme-info-bg border border-theme-info-border rounded-lg p-4">
              <h3 className="text-sm font-medium text-theme-info-fg mb-1">Last Connected</h3>
              <p className="text-sm text-theme-info-fg">{lastConnected.toLocaleString()}</p>
            </div>
          )}
        </div>
      </div>
    </PageContainer>
  );
};