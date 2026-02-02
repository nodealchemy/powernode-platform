import React, { useState, useEffect } from 'react';
import { twoFactorApi } from '@/shared/services/account/twoFactorApi';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';
import { Copy, Check } from 'lucide-react';
import { sanitizeQrCode } from '@/shared/utils/sanitizeHtml';

interface TwoFactorSetupProps {
  onComplete?: () => void;
  onCancel?: () => void;
}

export const TwoFactorSetup: React.FC<TwoFactorSetupProps> = ({ onComplete, onCancel }) => {
  const [step, setStep] = useState<'enabling' | 'setup' | 'verify' | 'complete'>('enabling');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [qrCode, setQrCode] = useState<string | null>(null);
  const [manualKey, setManualKey] = useState<string | null>(null);
  const [backupCodes, setBackupCodes] = useState<string[]>([]);
  const [verificationCode, setVerificationCode] = useState('');
  const [isVerifying, setIsVerifying] = useState(false);

  useEffect(() => {
    handleEnable2FA();
  }, []);

  const handleEnable2FA = async () => {
    setLoading(true);
    setError(null);
    
    try {
      const response = await twoFactorApi.enable();

      if (response.success) {
        setQrCode(response.qr_code || null);
        setManualKey(response.manual_entry_key || null);
        setBackupCodes(response.backup_codes || []);
        setStep('setup');
      } else {
        setError(response.error || 'Failed to enable two-factor authentication');
      }
    } catch {
      setError('Failed to enable two-factor authentication');
    } finally {
      setLoading(false);
    }
  };

  const handleVerifySetup = async () => {
    if (!verificationCode.trim()) {
      setError('Please enter the verification code from your authenticator app');
      return;
    }

    setIsVerifying(true);
    setError(null);

    try {
      const response = await twoFactorApi.verifySetup(verificationCode);
      
      if (response.success) {
        setStep('complete');
      } else {
        setError(response.error || 'Invalid verification code');
      }
    } catch {
      setError('Failed to verify the code. Please try again.');
    } finally {
      setIsVerifying(false);
    }
  };

  const formatManualKey = (key: string) => {
    return key.match(/.{1,4}/g)?.join(' ') || key;
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-8">
        <LoadingSpinner />
        <p className="mt-4 text-theme-secondary">Setting up two-factor authentication...</p>
      </div>
    );
  }

  return (
    <div className="max-w-md mx-auto">
      {step === 'setup' && (
        <div className="space-y-6">
          <div className="text-center">
            <h2 className="text-2xl font-bold text-theme-primary mb-2">
              Set Up Two-Factor Authentication
            </h2>
            <p className="text-theme-secondary">
              Scan the QR code below with your authenticator app or enter the setup key manually.
            </p>
          </div>

          {qrCode && (
            <div className="flex flex-col items-center space-y-4">
              <div 
                className="p-4 bg-theme-surface border border-theme rounded-lg"
                dangerouslySetInnerHTML={{ __html: sanitizeQrCode(qrCode) }}
              />
              <p className="text-sm text-theme-secondary text-center">
                Scan this QR code with Google Authenticator, Authy, or another TOTP app
              </p>
            </div>
          )}

          {manualKey && (
            <div className="space-y-2">
              <label className="block text-sm font-medium text-theme-primary">
                Manual Setup Key (if you can't scan the QR code):
              </label>
              <div className="flex items-center space-x-2">
                <FormField
                  label=""
                  type="text"
                  value={formatManualKey(manualKey)}
                  onChange={() => {}}
                  disabled={true}
                  className="flex-1 font-mono text-sm"
                />
                <Button
                  type="button"
                  onClick={() => copyToClipboard(manualKey)}
                  variant="primary"
                  size="sm"
                >
                  <Copy className="w-4 h-4 mr-1" />
                  Copy
                </Button>
              </div>
            </div>
          )}

          <FormField
            label="Enter the 6-digit code from your authenticator app:"
            type="text"
            value={verificationCode}
            onChange={(value) => setVerificationCode(value.replace(/\D/g, '').slice(0, 6))}
            placeholder="123456"
            className="text-center text-lg font-mono tracking-widest"
          />

          {error && (
            <div className="p-3 bg-theme-error-background border border-theme-error rounded-md">
              <p className="text-theme-error text-sm">{error}</p>
            </div>
          )}

          <div className="flex space-x-3">
            <Button
              type="button"
              onClick={onCancel}
              disabled={isVerifying}
              variant="outline"
              fullWidth
            >
              Cancel
            </Button>
            <Button
              type="button"
              onClick={handleVerifySetup}
              disabled={isVerifying || verificationCode.length !== 6}
              variant="primary"
              loading={isVerifying}
              fullWidth
            >
              {isVerifying ? 'Verifying...' : 'Verify & Enable'}
            </Button>
          </div>
        </div>
      )}

      {step === 'verify' && (
        <div className="text-center space-y-4">
          <LoadingSpinner />
          <p className="text-theme-secondary">Verifying your code...</p>
        </div>
      )}

      {step === 'complete' && (
        <div className="space-y-6">
          <div className="text-center">
            <div className="w-16 h-16 mx-auto bg-theme-success-background rounded-full flex items-center justify-center mb-4">
              <svg className="w-8 h-8 text-theme-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <h2 className="text-2xl font-bold text-theme-primary mb-2">
              Two-Factor Authentication Enabled!
            </h2>
            <p className="text-theme-secondary">
              Your account is now protected with two-factor authentication.
            </p>
          </div>

          {backupCodes.length > 0 && (
            <div className="space-y-4">
              <div className="p-4 bg-theme-warning-background border border-theme-warning rounded-md">
                <p className="text-theme-warning text-sm font-medium mb-2">
                  ⚠️ Save your backup codes
                </p>
                <p className="text-theme-warning text-sm opacity-90">
                  Store these backup codes in a safe place. You can use them to access your account if you lose your authenticator device.
                </p>
              </div>

              <div className="space-y-2">
                <label className="block text-sm font-medium text-theme-primary">
                  Backup Codes (use only once each):
                </label>
                <div className="p-3 bg-theme-surface border border-theme rounded-md">
                  {backupCodes.map((code, index) => (
                    <div key={index} className="font-mono text-sm text-theme-primary py-1">
                      {code}
                    </div>
                  ))}
                </div>
                <Button
                  type="button"
                  onClick={() => copyToClipboard(backupCodes.join('\n'))}
                  variant="primary"
                  size="sm"
                  fullWidth
                >
                  <Copy className="w-4 h-4 mr-1" />
                  Copy Backup Codes
                </Button>
              </div>
            </div>
          )}

          <Button
            type="button"
            onClick={onComplete}
            variant="primary"
            fullWidth
          >
            <Check className="w-4 h-4 mr-1" />
            Done
          </Button>
        </div>
      )}
    </div>
  );
};

