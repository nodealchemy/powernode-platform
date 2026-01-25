import React, { useState, useEffect } from 'react';
import { twoFactorApi } from '@/shared/services/account/twoFactorApi';
import { TwoFactorSetup } from '@/features/account/auth/components/TwoFactorSetup';
import Modal from '@/shared/components/ui/Modal';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

export const TwoFactorSettings: React.FC = () => {
  const [status, setStatus] = useState<{
    enabled: boolean;
    backupCodesCount: number;
    enabledAt?: string;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showSetup, setShowSetup] = useState(false);
  const [showDisableConfirm, setShowDisableConfirm] = useState(false);
  const [showBackupCodes, setShowBackupCodes] = useState(false);
  const [backupCodes, setBackupCodes] = useState<string[]>([]);
  const [isDisabling, setIsDisabling] = useState(false);
  const [isRegenerating, setIsRegenerating] = useState(false);

  useEffect(() => {
    fetchStatus();
  }, []);

  const fetchStatus = async () => {
    setLoading(true);
    setError(null);
    
    try {
      const response = await twoFactorApi.getStatus();
      
      if (response.success) {
        setStatus({
          enabled: response.two_factor_enabled,
          backupCodesCount: response.backup_codes_count,
          enabledAt: response.enabled_at
        });
      } else {
        setError('Failed to load two-factor authentication status');
      }
    } catch (error) {
      setError('Failed to load two-factor authentication status');
    } finally {
      setLoading(false);
    }
  };

  const handleDisable2FA = async () => {
    setIsDisabling(true);
    setError(null);

    try {
      const response = await twoFactorApi.disable();
      
      if (response.success) {
        setStatus({
          enabled: false,
          backupCodesCount: 0
        });
        setShowDisableConfirm(false);
      } else {
        setError(response.error || 'Failed to disable two-factor authentication');
      }
    } catch (error) {
      setError('Failed to disable two-factor authentication');
    } finally {
      setIsDisabling(false);
    }
  };

  const handleViewBackupCodes = async () => {
    try {
      const response = await twoFactorApi.getBackupCodes();
      
      if (response.success) {
        setBackupCodes(response.backup_codes);
        setShowBackupCodes(true);
      } else {
        setError(response.error || 'Failed to load backup codes');
      }
    } catch (error) {
      setError('Failed to load backup codes');
    }
  };

  const handleRegenerateBackupCodes = async () => {
    setIsRegenerating(true);
    setError(null);

    try {
      const response = await twoFactorApi.regenerateBackupCodes();
      
      if (response.success) {
        setBackupCodes(response.backup_codes);
        setStatus(prev => prev ? { ...prev, backupCodesCount: response.backup_codes.length } : null);
      } else {
        setError(response.error || 'Failed to regenerate backup codes');
      }
    } catch (error) {
      setError('Failed to regenerate backup codes');
    } finally {
      setIsRegenerating(false);
    }
  };

  const copyBackupCodes = () => {
    navigator.clipboard.writeText(backupCodes.join('\n'));
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <LoadingSpinner />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-medium text-theme-primary mb-2">
          Two-Factor Authentication
        </h3>
        <p className="text-theme-secondary text-sm">
          Add an extra layer of security to your account with two-factor authentication.
        </p>
      </div>

      {error && (
        <div className="p-3 bg-theme-error-background border border-theme-error-border rounded-md">
          <p className="text-theme-error text-sm">{error}</p>
        </div>
      )}

      <div className="border border-theme rounded-lg p-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center">
            <div className={`w-3 h-3 rounded-full mr-3 ${
              status?.enabled ? 'bg-theme-success' : 'bg-theme-secondary'
            }`} />
            <div>
              <p className="font-medium text-theme-primary">
                Two-Factor Authentication
              </p>
              <p className="text-sm text-theme-secondary">
                {status?.enabled ? 'Enabled' : 'Disabled'}
                {status?.enabledAt && ` • Enabled on ${formatDate(status.enabledAt)}`}
              </p>
            </div>
          </div>
          
          {status?.enabled ? (
            <button
              onClick={() => setShowDisableConfirm(true)}
              className="btn-theme btn-theme-outline border-theme-error text-theme-error hover:bg-theme-error-background text-sm"
            >
              Disable
            </button>
          ) : (
            <button
              onClick={() => setShowSetup(true)}
              className="px-4 py-2 text-sm bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-hover"
            >
              Enable 2FA
            </button>
          )}
        </div>

        {status?.enabled && (
          <div className="mt-4 pt-4 border-t border-theme space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-theme-primary">
                  Backup Codes
                </p>
                <p className="text-xs text-theme-secondary">
                  You have {status.backupCodesCount} backup codes remaining
                </p>
              </div>
              <div className="flex space-x-2">
                <button
                  onClick={handleViewBackupCodes}
                  className="px-3 py-1 text-xs border border-theme rounded text-theme-primary hover:bg-theme-surface"
                >
                  View Codes
                </button>
                <button
                  onClick={handleRegenerateBackupCodes}
                  disabled={isRegenerating}
                  className="px-3 py-1 text-xs bg-theme-interactive-primary text-white rounded hover:bg-theme-interactive-hover disabled:opacity-50"
                >
                  {isRegenerating ? 'Regenerating...' : 'Regenerate'}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Setup Modal */}
      <Modal
        isOpen={showSetup}
        onClose={() => setShowSetup(false)}
        title="Enable Two-Factor Authentication"
        maxWidth="lg"
      >
        <TwoFactorSetup
          onComplete={() => {
            setShowSetup(false);
            fetchStatus();
          }}
          onCancel={() => setShowSetup(false)}
        />
      </Modal>

      {/* Disable Confirmation Modal */}
      <Modal
        isOpen={showDisableConfirm}
        onClose={() => setShowDisableConfirm(false)}
        title="Disable Two-Factor Authentication"
      >
        <div className="space-y-4">
          <p className="text-theme-secondary">
            Are you sure you want to disable two-factor authentication? This will make your account less secure.
          </p>
          
          <div className="p-3 bg-theme-warning-background border border-theme-warning rounded-md">
            <p className="text-theme-warning text-sm">
              <strong>Warning:</strong> Disabling 2FA will remove the additional security layer from your account.
            </p>
          </div>

          <div className="flex space-x-3">
            <button
              onClick={() => setShowDisableConfirm(false)}
              disabled={isDisabling}
              className="flex-1 px-4 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              onClick={handleDisable2FA}
              disabled={isDisabling}
              className="btn-theme btn-theme-danger flex-1"
            >
              {isDisabling ? 'Disabling...' : 'Disable 2FA'}
            </button>
          </div>
        </div>
      </Modal>

      {/* Backup Codes Modal */}
      <Modal
        isOpen={showBackupCodes}
        onClose={() => setShowBackupCodes(false)}
        title="Backup Codes"
      >
        <div className="space-y-4">
          <p className="text-theme-secondary text-sm">
            Use these codes to access your account if you lose your authenticator device. Each code can only be used once.
          </p>

          <div className="p-4 bg-theme-surface border border-theme rounded-md">
            {backupCodes.map((code, index) => (
              <div key={index} className="font-mono text-sm text-theme-primary py-1">
                {code}
              </div>
            ))}
          </div>

          <div className="flex space-x-3">
            <button
              onClick={copyBackupCodes}
              className="flex-1 px-4 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface"
            >
              Copy Codes
            </button>
            <button
              onClick={handleRegenerateBackupCodes}
              disabled={isRegenerating}
              className="flex-1 px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-hover disabled:opacity-50"
            >
              {isRegenerating ? 'Regenerating...' : 'Regenerate'}
            </button>
          </div>

          <div className="p-3 bg-theme-warning-background border border-theme-warning rounded-md">
            <p className="text-theme-warning text-xs">
              <strong>Important:</strong> Store these codes in a safe place. If you regenerate codes, the old ones will no longer work.
            </p>
          </div>
        </div>
      </Modal>
    </div>
  );
};

