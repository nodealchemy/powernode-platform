import React, { useState } from 'react';
import { twoFactorApi } from '@/shared/services/account/twoFactorApi';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';
import { AuthResponse } from '@/features/account/auth/services/authAPI';
import { Lock } from 'lucide-react';

interface TwoFactorVerificationProps {
  verificationToken: string;
  onSuccess: (data: AuthResponse) => void;
  onError: (error: string) => void;
  onCancel?: () => void;
}

export const TwoFactorVerification: React.FC<TwoFactorVerificationProps> = ({ 
  verificationToken, 
  onSuccess, 
  onError,
  onCancel 
}) => {
  const [code, setCode] = useState('');
  const [isVerifying, setIsVerifying] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!code.trim()) {
      setError('Please enter your verification code');
      return;
    }

    if (code.length !== 6 && code.length !== 8) {
      setError('Please enter a valid 6-digit code or 8-digit backup code');
      return;
    }

    setIsVerifying(true);
    setError(null);

    try {
      const response = await twoFactorApi.verifyLogin(verificationToken, code);

      if (response.success) {
        onSuccess(response);
      } else {
        setError(response.error || 'Invalid verification code');
      }
    } catch (_error) {
      setError('Failed to verify code. Please try again.');
      onError('Failed to verify code. Please try again.');
    } finally {
      setIsVerifying(false);
    }
  };

  const handleCodeChange = (value: string) => {
    // Allow only digits and limit length
    const cleanValue = value.replace(/\D/g, '');
    if (cleanValue.length <= 8) {
      setCode(cleanValue);
      setError(null);
    }
  };

  return (
    <div className="max-w-md mx-auto space-y-6">
      <div className="text-center">
        <div className="w-16 h-16 mx-auto bg-theme-info-background rounded-full flex items-center justify-center mb-4">
          <svg className="w-8 h-8 text-theme-info" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} 
                  d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
          </svg>
        </div>
        <h2 className="text-2xl font-bold text-theme-primary mb-2">
          Two-Factor Authentication Required
        </h2>
        <p className="text-theme-secondary">
          Please enter the verification code from your authenticator app or use a backup code.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <FormField
          label="Verification Code"
          type="text"
          value={code}
          onChange={handleCodeChange}
          placeholder="Enter 6-digit code or backup code"
          className="text-center text-lg font-mono tracking-widest"
          disabled={isVerifying}
          helpText="Enter the 6-digit code from your authenticator app, or an 8-digit backup code"
        />

        {error && (
          <div className="p-3 bg-theme-error-background border border-theme-error rounded-md">
            <p className="text-theme-error text-sm">{error}</p>
          </div>
        )}

        <div className="flex space-x-3">
          {onCancel && (
            <Button
              type="button"
              onClick={onCancel}
              disabled={isVerifying}
              variant="outline"
              fullWidth
            >
              Cancel
            </Button>
          )}
          <Button
            type="submit"
            disabled={isVerifying || !code.trim()}
            variant="primary"
            loading={isVerifying}
            fullWidth
          >
            {!isVerifying && <Lock className="w-4 h-4 mr-1" />}
            {isVerifying ? 'Verifying...' : 'Verify'}
          </Button>
        </div>
      </form>

      <div className="text-center">
        <p className="text-xs text-theme-tertiary">
          Having trouble? Contact support or use a backup code if you've lost access to your authenticator app.
        </p>
      </div>
    </div>
  );
};

