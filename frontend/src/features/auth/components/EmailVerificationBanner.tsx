import React from 'react';
import { useAppDispatch, useAppSelector } from '@/shared/hooks/redux';
import { resendVerificationEmail, clearResendVerificationSuccess } from '@/shared/services/slices/authSlice';
import { AlertTriangle, Mail, CheckCircle, X } from 'lucide-react';

interface EmailVerificationBannerProps {
  onDismiss?: () => void;
  showDismiss?: boolean;
}

export const EmailVerificationBanner: React.FC<EmailVerificationBannerProps> = ({ 
  onDismiss,
  showDismiss = false 
}) => {
  const dispatch = useAppDispatch();
  const { 
    user,
    resendingVerification,
    resendVerificationSuccess,
    resendCooldown
  } = useAppSelector((state) => state.auth);

  // Don't show if user is verified or not logged in
  if (!user || user.email_verified) {
    return null;
  }

  const handleResendVerification = () => {
    dispatch(resendVerificationEmail());
  };

  const handleDismissSuccess = () => {
    dispatch(clearResendVerificationSuccess());
  };

  if (resendVerificationSuccess) {
    return (
      <div className="bg-theme-success-subtle border-l-4 border-theme-success p-4 mb-4">
        <div className="flex items-start">
          <CheckCircle className="h-5 w-5 text-theme-success flex-shrink-0 mt-0.5" />
          <div className="ml-3 flex-1">
            <h3 className="text-sm font-medium text-theme-success">
              Verification Email Sent
            </h3>
            <p className="mt-1 text-sm text-theme-success-muted">
              Please check your email at <strong>{user.email}</strong> and click the verification link.
            </p>
          </div>
          <button
            onClick={handleDismissSuccess}
            className="ml-auto flex-shrink-0 p-1 text-theme-success hover:text-theme-success-darker"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-theme-warning-subtle border-l-4 border-theme-warning p-4 mb-4">
      <div className="flex items-start">
        <AlertTriangle className="h-5 w-5 text-theme-warning flex-shrink-0 mt-0.5" />
        <div className="ml-3 flex-1">
          <h3 className="text-sm font-medium text-theme-warning">
            Email Verification Required
          </h3>
          <p className="mt-1 text-sm text-theme-warning-muted">
            Please verify your email address <strong>{user.email}</strong> to secure your account and access all features.
          </p>
          <div className="mt-3 flex items-center space-x-3">
            <button
              onClick={handleResendVerification}
              disabled={resendingVerification || resendCooldown > 0}
              className="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-theme-warning bg-theme-warning-subtle hover:bg-theme-warning-hover disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <Mail className="h-4 w-4 mr-1" />
              {resendingVerification ? 'Sending...' : 
               resendCooldown > 0 ? `Resend in ${resendCooldown}s` : 
               'Resend Verification'}
            </button>
            <span className="text-xs text-theme-muted">
              Check your spam folder if you don't see the email
            </span>
          </div>
        </div>
        {showDismiss && onDismiss && (
          <button
            onClick={onDismiss}
            className="ml-auto flex-shrink-0 p-1 text-theme-warning hover:text-theme-warning-darker"
          >
            <X className="h-4 w-4" />
          </button>
        )}
      </div>
    </div>
  );
};

export default EmailVerificationBanner;