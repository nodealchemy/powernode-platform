import React, { useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { RefreshCw } from 'lucide-react';

export const TestWebSocket: React.FC = () => {
  const { user, accessToken } = useSelector((state: RootState) => state.auth);
  const { isConnected, error, lastConnected } = useWebSocket();
  
  useEffect(() => {
  }, [user, accessToken, isConnected, error, lastConnected]);
  
  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'WebSocket Test', icon: '🧪' }
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
                  accessToken ? 'bg-theme-success-background text-theme-success' : 'bg-theme-error-background text-theme-error'
                }`}>
                  {accessToken ? 'Present' : 'Missing'}
                </span>
              </p>
            </div>
            <div>
              <label className="text-sm font-medium text-theme-secondary">Connection Status</label>
              <p className="mt-1">
                <span className={`inline-flex items-center px-2 py-1 text-xs font-medium rounded-full ${
                  isConnected ? 'bg-theme-success-background text-theme-success' : 'bg-theme-error-background text-theme-error'
                }`}>
                  <span className={`w-2 h-2 rounded-full mr-1.5 ${
                    isConnected ? 'bg-theme-success' : 'bg-theme-error'
                  }`} />
                  {isConnected ? 'Connected' : 'Disconnected'}
                </span>
              </p>
            </div>
          </div>
          
          {error && (
            <div className="bg-theme-error-background border border-theme-error-border rounded-lg p-4">
              <h3 className="text-sm font-medium text-theme-error mb-1">Error</h3>
              <p className="text-sm text-theme-error">{error}</p>
            </div>
          )}
          
          {lastConnected && (
            <div className="bg-theme-info-background border border-theme-info-border rounded-lg p-4">
              <h3 className="text-sm font-medium text-theme-info mb-1">Last Connected</h3>
              <p className="text-sm text-theme-info">{lastConnected.toLocaleString()}</p>
            </div>
          )}
        </div>
      </div>
    </PageContainer>
  );
};