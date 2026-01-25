import React, { useEffect, useState } from 'react';

import { useSearchParams, useNavigate } from 'react-router-dom';

import { CheckCircle, AlertTriangle, Mail, ArrowRight } from 'lucide-react';

import { authApi } from '@/features/account/auth/services/authAPI';

import { useNotifications } from '@/shared/hooks/useNotifications';
import { ErrorHandler } from '@/shared/utils/errorHandling';


interface VerificationResult {
  success: boolean;
  message: string;
  user?: {
    id: string;
    email: string;
    email_verified: boolean;
  };
}

interface VerifyEmailResponse {
  success?: boolean;
  message?: string;
  error?: string;
  user?: VerificationResult['user'];
}

const EmailVerificationPage: React.FC = () => {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { addNotification } = useNotifications();
  
  const [isVerifying, setIsVerifying] = useState(false);
  const [verificationResult, setVerificationResult] = useState<VerificationResult | null>(null);
  
  const token = searchParams.get('token');

  useEffect(() => {

    if (token && !isVerifying && !verificationResult) {
      handleVerification(token);
    }
  }, [token, isVerifying, verificationResult]);

  const handleVerification = async (verificationToken: string) => {
    setIsVerifying(true);
    
    try {
      const response = await authApi.verifyEmail(verificationToken);
      
      // Handle API response properly - response.data contains the actual response
      const data = response.data as VerifyEmailResponse;

      if (data.success) {
        setVerificationResult({
          success: true,
          message: data.message || 'Email verified successfully!',
          user: data.user
        });

        addNotification({
          type: 'success',
          title: 'Email Verified',
          message: 'Your email has been successfully verified. You can now access all features.',
        });
      } else {
        setVerificationResult({
          success: false,
          message: data.error || 'Verification failed'
        });
      }
    } catch (error: unknown) {
      const errorMessage = ErrorHandler.getUserMessage(error);
      setVerificationResult({
        success: false,
        message: errorMessage
      });
    } finally {
      setIsVerifying(false);
    }
  };

  const handleContinue = () => {
    // Redirect to login page or dashboard depending on authentication state
    const accessToken = localStorage.getItem('access_token');
    if (accessToken) {
      navigate('/app');
    } else {
      navigate('/login', { state: { verified: true } });
    }
  };

  const handleResendVerification = () => {
    navigate('/login', { state: { resendVerification: true } });
  };

  // No token provided
  if (!token) {
    return (
      <div className="min-h-screen bg-theme-surface flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-md w-full space-y-8 text-center">
          <div>
            <AlertTriangle className="mx-auto h-12 w-12 text-theme-warning" />
            <h2 className="mt-6 text-3xl font-bold text-theme-primary">
              Invalid Verification Link
            </h2>
            <p className="mt-2 text-theme-muted">
              This verification link appears to be invalid or incomplete.
            </p>
          </div>
          <div className="flex flex-col space-y-3">
            <button
              onClick={() => handleResendVerification?.()}
              className="btn-theme btn-theme-primary btn-theme-md w-full flex justify-center items-center gap-2"
            >
              <Mail className="h-4 w-4" />
              Request New Verification Email
            </button>
            <button
              onClick={() => navigate('/login')}
              className="text-theme-muted hover:text-theme-primary text-sm"
            >
              Back to Login
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-theme-surface flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md w-full space-y-8 text-center">
        {isVerifying ? (
          // Loading State
          <div>
            <div className="animate-spin mx-auto h-12 w-12 border-4 border-theme-primary border-t-transparent rounded-full"></div>
            <h2 className="mt-6 text-3xl font-bold text-theme-primary">
              Verifying Email
            </h2>
            <p className="mt-2 text-theme-muted">
              Please wait while we verify your email address...
            </p>
          </div>
        ) : verificationResult ? (
          // Result State
          <div>
            {verificationResult.success ? (
              // Success
              <>
                <CheckCircle className="mx-auto h-12 w-12 text-theme-success" />
                <h2 className="mt-6 text-3xl font-bold text-theme-primary">
                  Email Verified!
                </h2>
                <p className="mt-2 text-theme-muted">
                  {verificationResult.message}
                </p>
                {verificationResult.user && (
                  <p className="mt-1 text-sm text-theme-muted">
                    <strong>{verificationResult.user.email}</strong> has been successfully verified.
                  </p>
                )}
                <div className="mt-8">
                  <button
                    onClick={() => handleContinue?.()}
                    className="btn-theme btn-theme-primary btn-theme-md w-full flex justify-center items-center gap-2 group"
                  >
                    Continue to Dashboard
                    <ArrowRight className="h-4 w-4 group-hover:translate-x-1 transition-transform" />
                  </button>
                </div>
              </>
            ) : (
              // Error
              <>
                <AlertTriangle className="mx-auto h-12 w-12 text-theme-error" />
                <h2 className="mt-6 text-3xl font-bold text-theme-primary">
                  Verification Failed
                </h2>
                <p className="mt-2 text-theme-muted">
                  {verificationResult.message}
                </p>
                <div className="mt-8 flex flex-col space-y-3">
                  <button
                    onClick={() => handleResendVerification?.()}
                    className="btn-theme btn-theme-primary btn-theme-md w-full flex justify-center items-center gap-2"
                  >
                    <Mail className="h-4 w-4" />
                    Request New Verification Email
                  </button>
                  <button
                    onClick={() => navigate('/login')}
                    className="text-theme-muted hover:text-theme-primary text-sm"
                  >
                    Back to Login
                  </button>
                </div>
              </>
            )}
          </div>
        ) : null}
      </div>
    </div>
  );
};

export default EmailVerificationPage;
