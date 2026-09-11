import React, { useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { CheckCircle } from 'lucide-react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { resendVerificationEmail, clearResendVerificationSuccess, decrementResendCooldown } from '@/shared/services';
import { usePolling } from '@/shared/hooks/usePolling';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { authApi } from '@/features/account/auth/services/authAPI';
import { getErrorMessage, getErrorStatus } from '@/shared/utils/errorHandling';

// Envelope shape from Api::V1::Auth::EmailVerificationsController#verify.
// render_success is called with a single positional hash, so the message
// (and user, on a fresh verification) end up nested under `data`, not at
// the envelope's top level; render_error's message is flat (`error`).
interface VerifyEmailEnvelope {
  success?: boolean;
  data?: { message?: string; user?: { id: string; email: string; email_verified: boolean } };
}

type TokenState = 'idle' | 'verifying' | 'success' | 'expired' | 'invalid';

export const VerifyEmailPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { addNotification } = useNotifications();
  const {
    user,
    resendingVerification,
    resendVerificationSuccess,
    resendCooldown,
    error
  } = useSelector((state: RootState) => state.auth);

  const [tokenState, setTokenState] = useState<TokenState>('idle');
  const [tokenMessage, setTokenMessage] = useState('');
  // Guards against a double call: React 18 StrictMode runs a mount-time
  // effect twice in dev, and the token is single-use, so a naive second
  // call would show "invalid" right after a real success.
  const verifyStartedRef = useRef(false);

  // Countdown timer for resend cooldown
  usePolling(() => dispatch(decrementResendCooldown()), 1000, {
    enabled: resendCooldown > 0,
    deps: [resendCooldown, dispatch],
  });

  // Clear success message after 5 seconds
  useEffect(() => {

    if (resendVerificationSuccess) {
      const timeout = setTimeout(() => {
        dispatch(clearResendVerificationSuccess());
      }, 5000);

      return () => clearTimeout(timeout);
    }
  }, [resendVerificationSuccess, dispatch]);

  // Verify a token present in the emailed link (worker/app/mailers/notification_mailer.rb
  // sends `${frontend_url}/verify-email?token=...`). Runs once, at mount, deliberately —
  // see verifyStartedRef above.
  useEffect(() => {
    const token = searchParams.get('token');
    if (!token || verifyStartedRef.current) return;
    verifyStartedRef.current = true;

    // Strip the token from the address bar immediately, before the network
    // call even resolves: it is single-use, and must never sit in browser
    // history or leak through a Referer header on whatever page comes next.
    // Never logged, anywhere, in any form.
    const url = new URL(window.location.href);
    url.searchParams.delete('token');
    window.history.replaceState({}, '', `${url.pathname}${url.search}${url.hash}`);

    setTokenState('verifying');
    authApi.verifyEmail(token)
      .then((response) => {
        const envelope = response.data as VerifyEmailEnvelope;
        const message = envelope.data?.message || 'Email verified successfully!';
        setTokenMessage(message);
        setTokenState('success');
        addNotification({
          type: 'success',
          title: 'Email Verified',
          message: 'Your email has been successfully verified.',
        });
      })
      .catch((err) => {
        setTokenMessage(getErrorMessage(err));
        setTokenState(getErrorStatus(err) === 422 ? 'expired' : 'invalid');
      });
    // Runs once at mount by design (see verifyStartedRef) — searchParams
    // intentionally excluded so a later, unrelated URL change never re-fires it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleResendVerification = () => {
    if (resendCooldown === 0) {
      dispatch(resendVerificationEmail());
    }
  };

  if (tokenState === 'verifying') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-theme-background-secondary py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-md w-full text-center">
          <div className="animate-spin mx-auto h-12 w-12 border-4 border-theme-primary border-t-transparent rounded-full" />
          <h2 className="mt-6 text-3xl font-extrabold text-theme-primary">Verifying your email</h2>
          <p className="mt-2 text-sm text-theme-secondary">Please wait a moment…</p>
        </div>
      </div>
    );
  }

  if (tokenState === 'success') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-theme-background-secondary py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-md w-full text-center space-y-8">
          <div>
            <CheckCircle className="mx-auto h-12 w-12 text-theme-success-fg" />
            <h2 className="mt-6 text-3xl font-extrabold text-theme-primary">Email verified</h2>
            <p className="mt-2 text-sm text-theme-secondary">{tokenMessage}</p>
          </div>
          <button
            onClick={() => navigate('/app')}
            className="btn-theme btn-theme-primary btn-theme-md w-full"
          >
            Continue to Dashboard
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-theme-background-secondary py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md w-full space-y-8">
        <div className="text-center">
          <div className="mx-auto h-12 w-12 flex items-center justify-center rounded-xl bg-theme-background-tertiary">
            <svg className="h-6 w-6 text-theme-interactive-secondary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.732-.833-2.464 0L4.35 16.5c-.77.833.192 2.5 1.732 2.5z" />
            </svg>
          </div>
          <h2 className="mt-6 text-3xl font-extrabold text-theme-primary">
            Verify your email
          </h2>
          <p className="mt-2 text-sm text-theme-secondary">
            We've sent a verification email to{' '}
            <span className="font-medium text-theme-primary">{user?.email}</span>
          </p>
        </div>

        {/* A token was present but rejected: say exactly what the backend said,
            distinguishing expired (ask for a new one) from invalid/already-used. */}
        {(tokenState === 'expired' || tokenState === 'invalid') && (
          <div className="alert-theme alert-theme-error rounded-md p-4">
            <div className="flex">
              <div className="ml-3">
                <h3 className="text-sm font-medium">
                  {tokenState === 'expired' ? 'Link expired' : 'Link invalid'}
                </h3>
                <div className="mt-2 text-sm">
                  <p>{tokenMessage}</p>
                </div>
              </div>
            </div>
          </div>
        )}

        <div className="alert-theme alert-theme-info rounded-md p-4">
          <div className="flex">
            <div className="ml-3">
              <h3 className="text-sm font-medium">
                Please check your email
              </h3>
              <div className="mt-2 text-sm">
                <p>
                  Click the verification link in your email to activate your account.
                  If you don't see the email, check your spam folder.
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* Success message */}
        {resendVerificationSuccess && (
          <div className="alert-theme alert-theme-success rounded-md p-4">
            <div className="flex">
              <div className="flex-shrink-0">
                <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                </svg>
              </div>
              <div className="ml-3">
                <p className="text-sm font-medium">
                  Verification email sent successfully!
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Error message */}
        {error && (
          <div className="alert-theme alert-theme-error rounded-md p-4">
            <div className="flex">
              <div className="flex-shrink-0">
                <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
                </svg>
              </div>
              <div className="ml-3">
                <p className="text-sm font-medium">
                  {error}
                </p>
              </div>
            </div>
          </div>
        )}

        <div className="text-center">
          <button
            className={`text-sm font-medium transition-colors ${
              resendCooldown > 0 || resendingVerification
                ? 'text-theme-tertiary cursor-not-allowed'
                : 'text-theme-link hover:text-theme-link-hover'
            }`}
            onClick={() => handleResendVerification?.()}
            disabled={resendCooldown > 0 || resendingVerification}
          >
            {resendingVerification ? (
              <span className="flex items-center justify-center">
                <svg className="animate-spin -ml-1 mr-2 h-4 w-4 text-theme-tertiary" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="m4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Sending...
              </span>
            ) : resendCooldown > 0 ? (
              `Resend verification email (${resendCooldown}s)`
            ) : (
              'Resend verification email'
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
