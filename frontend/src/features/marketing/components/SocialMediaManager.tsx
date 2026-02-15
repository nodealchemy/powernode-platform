import React, { useState } from 'react';
import { Share2, Plus } from 'lucide-react';
import { useSocialAccounts } from '../hooks/useSocialAccounts';
import { SocialAccountCard } from './SocialAccountCard';
import { ConnectSocialModal } from './ConnectSocialModal';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { logger } from '@/shared/utils/logger';

export const SocialMediaManager: React.FC = () => {
  const [showConnectModal, setShowConnectModal] = useState(false);

  const {
    accounts,
    loading,
    error,
    refresh,
    connectAccount,
    disconnectAccount,
    testConnection,
    refreshToken,
  } = useSocialAccounts();

  const handleTest = async (id: string) => {
    try {
      const result = await testConnection(id);
      logger.info('Connection test result:', result);
    } catch (err) {
      logger.error('Connection test failed:', err);
    }
  };

  const handleRefreshToken = async (id: string) => {
    try {
      await refreshToken(id);
    } catch (err) {
      logger.error('Token refresh failed:', err);
    }
  };

  const handleDisconnect = async (id: string) => {
    try {
      await disconnectAccount(id);
    } catch (err) {
      logger.error('Failed to disconnect account:', err);
    }
  };

  const handleConnect = async (data: { platform: Parameters<typeof connectAccount>[0]['platform']; auth_code: string; redirect_uri: string }) => {
    await connectAccount(data);
  };

  if (loading && accounts.length === 0) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner />
      </div>
    );
  }

  if (error) {
    return (
      <div className="card-theme p-6 text-center">
        <p className="text-theme-error">{error}</p>
        <button onClick={refresh} className="btn-theme btn-theme-secondary mt-4">Retry</button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Summary */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="card-theme p-4">
          <p className="text-sm text-theme-secondary">Connected Accounts</p>
          <p className="text-2xl font-semibold text-theme-primary">{accounts.length}</p>
        </div>
        <div className="card-theme p-4">
          <p className="text-sm text-theme-secondary">Active</p>
          <p className="text-2xl font-semibold text-theme-success">
            {accounts.filter(a => a.status === 'connected').length}
          </p>
        </div>
        <div className="card-theme p-4">
          <p className="text-sm text-theme-secondary">Needs Attention</p>
          <p className="text-2xl font-semibold text-theme-warning">
            {accounts.filter(a => a.status === 'expired' || a.status === 'error').length}
          </p>
        </div>
      </div>

      {/* Account List */}
      {accounts.length === 0 ? (
        <div className="card-theme p-12 text-center">
          <Share2 className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">No social accounts connected</h3>
          <p className="text-theme-secondary mb-4">Connect your social media accounts to manage posts and track performance.</p>
          <button onClick={() => setShowConnectModal(true)} className="btn-theme btn-theme-primary">
            <Plus className="w-4 h-4 mr-2 inline" /> Connect Account
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {accounts.map(account => (
            <SocialAccountCard
              key={account.id}
              account={account}
              onTest={handleTest}
              onRefreshToken={handleRefreshToken}
              onDisconnect={handleDisconnect}
            />
          ))}
        </div>
      )}

      {/* Connect Modal */}
      {showConnectModal && (
        <ConnectSocialModal
          onConnect={handleConnect}
          onClose={() => setShowConnectModal(false)}
        />
      )}
    </div>
  );
};
