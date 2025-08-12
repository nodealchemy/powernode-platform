import React, { useState, useEffect } from 'react';
import { twoFactorApi } from '../../services/twoFactorApi';
import { LoadingSpinner } from '../common/LoadingSpinner';

interface TwoFactorSetupProps {
  onComplete?: () => void;
  onCancel?: () => void;
}

const TwoFactorSetup: React.FC<TwoFactorSetupProps> = ({ onComplete, onCancel }) => {
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
    } catch (err) {
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
    } catch (err) {
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
                className="p-4 bg-white border rounded-lg"
                dangerouslySetInnerHTML={{ __html: qrCode }}
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
                <input
                  type="text"
                  value={formatManualKey(manualKey)}
                  readOnly
                  className="flex-1 px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary font-mono text-sm"
                />
                <button
                  type="button"
                  onClick={() => copyToClipboard(manualKey)}
                  className="px-3 py-2 text-sm bg-theme-interactive-primary hover:bg-theme-interactive-hover text-white rounded-md"
                >
                  Copy
                </button>
              </div>
            </div>
          )}

          <div className="space-y-2">
            <label htmlFor="verificationCode" className="block text-sm font-medium text-theme-primary">
              Enter the 6-digit code from your authenticator app:
            </label>
            <input
              id="verificationCode"
              type="text"
              value={verificationCode}
              onChange={(e) => setVerificationCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
              placeholder="123456"
              maxLength={6}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary text-center text-lg font-mono tracking-widest"
            />
          </div>

          {error && (
            <div className="p-3 bg-red-50 border border-red-200 rounded-md">
              <p className="text-red-700 text-sm">{error}</p>
            </div>
          )}

          <div className="flex space-x-3">
            <button
              type="button"
              onClick={onCancel}
              disabled={isVerifying}
              className="flex-1 px-4 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleVerifySetup}
              disabled={isVerifying || verificationCode.length !== 6}
              className="flex-1 px-4 py-2 bg-theme-interactive-primary hover:bg-theme-interactive-hover text-white rounded-md disabled:opacity-50"
            >
              {isVerifying ? 'Verifying...' : 'Verify & Enable'}
            </button>
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
            <div className="w-16 h-16 mx-auto bg-green-100 rounded-full flex items-center justify-center mb-4">
              <svg className="w-8 h-8 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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
              <div className="p-4 bg-yellow-50 border border-yellow-200 rounded-md">
                <p className="text-yellow-800 text-sm font-medium mb-2">
                  ⚠️ Save your backup codes
                </p>
                <p className="text-yellow-700 text-sm">
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
                <button
                  type="button"
                  onClick={() => copyToClipboard(backupCodes.join('\n'))}
                  className="w-full px-4 py-2 text-sm bg-theme-interactive-primary hover:bg-theme-interactive-hover text-white rounded-md"
                >
                  Copy Backup Codes
                </button>
              </div>
            </div>
          )}

          <button
            type="button"
            onClick={onComplete}
            className="w-full px-4 py-2 bg-theme-interactive-primary hover:bg-theme-interactive-hover text-white rounded-md"
          >
            Done
          </button>
        </div>
      )}
    </div>
  );
};

export default TwoFactorSetup;