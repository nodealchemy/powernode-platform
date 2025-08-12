import React, { useState } from 'react';
import { twoFactorApi } from '../../services/twoFactorApi';

interface TwoFactorVerificationProps {
  verificationToken: string;
  onSuccess: (data: any) => void;
  onError: (error: string) => void;
  onCancel?: () => void;
}

const TwoFactorVerification: React.FC<TwoFactorVerificationProps> = ({ 
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
    } catch (err) {
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
        <div className="w-16 h-16 mx-auto bg-blue-100 rounded-full flex items-center justify-center mb-4">
          <svg className="w-8 h-8 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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
        <div>
          <label htmlFor="code" className="block text-sm font-medium text-theme-primary mb-2">
            Verification Code
          </label>
          <input
            id="code"
            type="text"
            value={code}
            onChange={(e) => handleCodeChange(e.target.value)}
            placeholder="Enter 6-digit code or backup code"
            autoComplete="one-time-code"
            className="w-full px-4 py-3 border border-theme rounded-md bg-theme-surface text-theme-primary text-center text-lg font-mono tracking-widest focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
            disabled={isVerifying}
            autoFocus
          />
          <p className="mt-2 text-xs text-theme-tertiary">
            Enter the 6-digit code from your authenticator app, or an 8-digit backup code
          </p>
        </div>

        {error && (
          <div className="p-3 bg-red-50 border border-red-200 rounded-md">
            <p className="text-red-700 text-sm">{error}</p>
          </div>
        )}

        <div className="flex space-x-3">
          {onCancel && (
            <button
              type="button"
              onClick={onCancel}
              disabled={isVerifying}
              className="flex-1 px-4 py-3 border border-theme rounded-md text-theme-primary hover:bg-theme-surface disabled:opacity-50 transition-colors"
            >
              Cancel
            </button>
          )}
          <button
            type="submit"
            disabled={isVerifying || !code.trim()}
            className="flex-1 px-4 py-3 bg-theme-interactive-primary hover:bg-theme-interactive-hover text-white rounded-md disabled:opacity-50 transition-colors"
          >
            {isVerifying ? (
              <div className="flex items-center justify-center">
                <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Verifying...
              </div>
            ) : (
              'Verify'
            )}
          </button>
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

export default TwoFactorVerification;