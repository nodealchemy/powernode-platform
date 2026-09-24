import React, { useState, useEffect } from 'react';
import { ShieldCheck, ShieldOff, Key } from 'lucide-react';
import { twoFactorApi } from '@/shared/services/account/twoFactorApi';
import { TwoFactorSetup } from '@/features/account/auth/components/TwoFactorSetup';
import Modal from '@/shared/components/ui/Modal';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { isErrorWithResponse, getErrorMessage } from '@/shared/utils/errorHandling';

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
  const [disableCode, setDisableCode] = useState('');
  const [disableError, setDisableError] = useState<string | null>(null);
  const [isDisabling, setIsDisabling] = useState(false);

  const [showRegenerateConfirm, setShowRegenerateConfirm] = useState(false);
  const [regenerateCode, setRegenerateCode] = useState('');
  const [regenerateError, setRegenerateError] = useState<string | null>(null);
  const [isRegenerating, setIsRegenerating] = useState(false);

  // New backup codes are shown ONLY here, right after regenerating — the
  // server never lets them be fetched again afterward.
  const [newBackupCodes, setNewBackupCodes] = useState<string[]>([]);
  const [codesSaved, setCodesSaved] = useState(false);

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
    } catch (_error) {
      setError('Failed to load two-factor authentication status');
    } finally {
      setLoading(false);
    }
  };

  const openDisableConfirm = () => {
    setDisableCode('');
    setDisableError(null);
    setShowDisableConfirm(true);
  };

  const handleDisable2FA = async () => {
    if (!disableCode.trim()) {
      setDisableError('Enter a code from your authenticator app or an unused backup code');
      return;
    }

    setIsDisabling(true);
    setDisableError(null);

    try {
      const response = await twoFactorApi.disable(disableCode.trim());

      if (response.success) {
        setStatus({
          enabled: false,
          backupCodesCount: 0
        });
        setShowDisableConfirm(false);
      } else {
        setDisableError(response.error || 'Failed to disable two-factor authentication');
      }
    } catch (error) {
      // render_error responds with a non-2xx status, so axios rejects here
      // rather than resolving {success: false} — surface the server's
      // message when the rejection carries one, falling back otherwise.
      // Scoped to disableError (shown in the confirm modal), not the
      // page-level `error`, since the user is looking at the modal.
      setDisableError(isErrorWithResponse(error) ? getErrorMessage(error) : 'Failed to disable two-factor authentication');
    } finally {
      setIsDisabling(false);
    }
  };

  const openRegenerateConfirm = () => {
    setRegenerateCode('');
    setRegenerateError(null);
    setShowRegenerateConfirm(true);
  };

  const handleRegenerateBackupCodes = async () => {
    if (!regenerateCode.trim()) {
      setRegenerateError('Enter a code from your authenticator app or an unused backup code');
      return;
    }

    setIsRegenerating(true);
    setRegenerateError(null);

    try {
      const response = await twoFactorApi.regenerateBackupCodes(regenerateCode.trim());

      if (response.success) {
        const codes = response.backup_codes || [];
        setNewBackupCodes(codes);
        setCodesSaved(false);
        setStatus(prev => prev ? { ...prev, backupCodesCount: codes.length } : null);
        setShowRegenerateConfirm(false);
      } else {
        setRegenerateError(response.error || 'Failed to regenerate backup codes');
      }
    } catch (error) {
      // Same axios-rejects-on-non-2xx shape as handleDisable2FA above.
      setRegenerateError(isErrorWithResponse(error) ? getErrorMessage(error) : 'Failed to regenerate backup codes');
    } finally {
      setIsRegenerating(false);
    }
  };

  const copyBackupCodes = () => {
    navigator.clipboard.writeText(newBackupCodes.join('\n'));
  };

  const downloadBackupCodes = () => {
    const blob = new Blob([newBackupCodes.join('\n')], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'backup-codes.txt';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
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
      {error && <ErrorAlert message={error} />}

      <div className="border border-theme rounded-lg p-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center">
            <div className={`w-3 h-3 rounded-full mr-3 ${
              status?.enabled ? 'bg-theme-success-bg' : 'bg-theme-surface'
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
              onClick={openDisableConfirm}
              className="btn-theme btn-theme-outline border-theme-error-border text-theme-error-fg hover:bg-theme-error-bg text-sm"
            >
              Disable
            </button>
          ) : (
            <button
              onClick={() => setShowSetup(true)}
              className="px-4 py-2 text-sm bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover"
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
              <button
                onClick={openRegenerateConfirm}
                disabled={isRegenerating}
                className="px-3 py-1 text-xs bg-theme-interactive-primary text-white rounded hover:bg-theme-interactive-primary-hover disabled:opacity-50"
              >
                {isRegenerating ? 'Regenerating...' : 'Regenerate'}
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Setup Modal */}
      <Modal
        isOpen={showSetup}
        // Refreshes status on EVERY close path, not just the "Done" button
        // (onComplete below): the X / backdrop close reachable from here
        // would otherwise leave a stale "Disabled" status showing after a
        // successful verify that the user closed out of before clicking
        // Done (IMP-99e8e4701150 review N3). Harmless to call twice when
        // Done was clicked — fetchStatus is idempotent.
        onClose={() => { setShowSetup(false); fetchStatus(); }}
        title="Enable Two-Factor Authentication"
        icon={<ShieldCheck className="w-6 h-6" />}
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
        icon={<ShieldOff className="w-6 h-6" />}
      >
        <div className="space-y-4">
          <p className="text-theme-secondary">
            Are you sure you want to disable two-factor authentication? This will make your account less secure.
          </p>

          <div className="p-3 bg-theme-warning-bg border border-theme-warning-border rounded-md">
            <p className="text-theme-warning-fg text-sm">
              <strong>Warning:</strong> Disabling 2FA will remove the additional security layer from your account.
            </p>
          </div>

          <div className="space-y-2">
            <label className="block text-sm font-medium text-theme-primary">
              Enter a code from your authenticator app or a backup code to confirm:
            </label>
            <input
              type="text"
              value={disableCode}
              onChange={(e) => setDisableCode(e.target.value)}
              placeholder="123456"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary font-mono"
            />
          </div>

          {disableError && <ErrorAlert message={disableError} />}

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

      {/* Regenerate Confirmation Modal */}
      <Modal
        isOpen={showRegenerateConfirm}
        onClose={() => setShowRegenerateConfirm(false)}
        title="Regenerate Backup Codes"
        icon={<Key className="w-6 h-6" />}
      >
        <div className="space-y-4">
          <p className="text-theme-secondary text-sm">
            Regenerating will invalidate all existing backup codes, including any unused ones.
          </p>

          <div className="space-y-2">
            <label className="block text-sm font-medium text-theme-primary">
              Enter a code from your authenticator app or a backup code to confirm:
            </label>
            <input
              type="text"
              value={regenerateCode}
              onChange={(e) => setRegenerateCode(e.target.value)}
              placeholder="123456"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary font-mono"
            />
          </div>

          {regenerateError && <ErrorAlert message={regenerateError} />}

          <div className="flex space-x-3">
            <button
              onClick={() => setShowRegenerateConfirm(false)}
              disabled={isRegenerating}
              className="flex-1 px-4 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              onClick={handleRegenerateBackupCodes}
              disabled={isRegenerating}
              className="flex-1 px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover disabled:opacity-50"
            >
              {isRegenerating ? 'Regenerating...' : 'Regenerate'}
            </button>
          </div>
        </div>
      </Modal>

      {/* New Backup Codes Modal — shown ONCE, immediately after regenerating */}
      <Modal
        isOpen={newBackupCodes.length > 0}
        onClose={() => { setNewBackupCodes([]); setCodesSaved(false); }}
        title="New Backup Codes"
        icon={<Key className="w-6 h-6" />}
      >
        <div className="space-y-4">
          <p className="text-theme-secondary text-sm">
            Save these codes now — they will not be shown again. Each code can only be used once.
          </p>

          <div className="p-4 bg-theme-surface border border-theme rounded-md">
            {newBackupCodes.map((code, index) => (
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
              onClick={downloadBackupCodes}
              className="flex-1 px-4 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface"
            >
              Download
            </button>
          </div>

          <label className="flex items-start space-x-2 text-sm text-theme-secondary">
            <input
              type="checkbox"
              checked={codesSaved}
              onChange={(e) => setCodesSaved(e.target.checked)}
              className="mt-0.5"
            />
            <span>I have saved these backup codes.</span>
          </label>

          <button
            onClick={() => { setNewBackupCodes([]); setCodesSaved(false); }}
            disabled={!codesSaved}
            className="w-full px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover disabled:opacity-50"
          >
            Done
          </button>
        </div>
      </Modal>
    </div>
  );
};
