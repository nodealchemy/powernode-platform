import React, { useState, useEffect } from 'react';

import { Link, useNavigate, useLocation } from 'react-router-dom';

import { useDispatch, useSelector } from 'react-redux';

import { RootState, AppDispatch } from '@/shared/services';

import { login, clearError, getCurrentUser } from '@/shared/services/slices/authSlice';

import { addNotification } from '@/shared/services/slices/uiSlice';

import { EyeIcon, EyeSlashIcon, LockClosedIcon, EnvelopeIcon } from '@heroicons/react/24/outline';

import { ErrorHandler } from '@/shared/utils/errorHandling';
import { settingsApi } from '@/shared/services/settings/settingsApi';

import { TwoFactorVerification } from '@/features/account/auth/components/TwoFactorVerification';
import { DomainChangeNotice } from '@/shared/components/ui/DomainChangeNotice';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';


interface LocationState {
  from?: string;
}

export const LoginPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const navigate = useNavigate();
  const location = useLocation();
  
  const { error } = useSelector((state: RootState) => state.auth);
  
  const [formData, setFormData] = useState({
    email: '',
    password: '',
  });
  
  const [showPassword, setShowPassword] = useState(false);
  const [rememberMe, setRememberMe] = useState(false);
  const [requires2FA, setRequires2FA] = useState(false);
  const [verificationToken, setVerificationToken] = useState<string | null>(null);
  const [loginLoading, setLoginLoading] = useState(false);
  const [touched] = useState({ email: false, password: false });
  const [errors] = useState({ email: '', password: '' });
  const [copyrightText, setCopyrightText] = useState<string>('');
  
  // Clear error when component unmounts or user navigates away
  useEffect(() => {

    return () => {
      dispatch(clearError());
    };
  }, [dispatch]);

  // Load copyright text from admin settings
  useEffect(() => {
    const loadCopyright = async () => {
      try {
        const copyright = await settingsApi.getCopyright();
        const formattedCopyright = settingsApi.formatCopyright(copyright);
        setCopyrightText(formattedCopyright);
      } catch (_error) {
        // Fallback to default copyright text
        setCopyrightText(`© ${new Date().getFullYear()} Everett C. Haimes III. All rights reserved.`);
      }
    };

    loadCopyright();
  }, []);

  const stateFrom = (location.state as LocationState | null)?.from;
  const savedPath = localStorage.getItem('powernode_last_path');
  const from = stateFrom || (savedPath?.startsWith('/app') ? savedPath : null) || '/app';

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
    
    // Clear error when user starts typing
    if (error) {
      dispatch(clearError());
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoginLoading(true);
    
    try {
      // Use Redux login action exclusively - no double dispatch
      const result = await dispatch(login(formData)).unwrap();

      if (result.requires_2fa) {
        // Handle 2FA requirement
        setRequires2FA(true);
        setVerificationToken(result.verification_token || null);
        dispatch(addNotification({
          type: 'info',
          message: 'Please enter your two-factor authentication code.',
        }));
      } else {
        // Normal login success
        dispatch(addNotification({
          type: 'success',
          message: 'Login successful! Welcome back.',
        }));

        // Small delay to ensure Redux state has propagated before navigation
        setTimeout(() => {
          navigate(from, { replace: true });
        }, 100);
      }
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: ErrorHandler.getUserMessage(error),
      }));
    } finally {
      setLoginLoading(false);
    }
  };

  const handle2FASuccess = async (data: unknown) => {
    // Save tokens from successful 2FA verification
    const authData = data as { access_token?: string; refresh_token?: string };
    if (authData.access_token) {
      localStorage.setItem('access_token', authData.access_token);
    }
    if (authData.refresh_token) {
      localStorage.setItem('refresh_token', authData.refresh_token);
    }

    try {
      // Get current user to update auth state properly
      await dispatch(getCurrentUser(false)).unwrap();
      
      dispatch(addNotification({
        type: 'success',
        message: 'Two-factor authentication successful! Welcome back.',
      }));
      
      // Small delay to ensure Redux state has propagated before navigation
      setTimeout(() => {
        navigate(from, { replace: true });
      }, 100);
    } catch (_error) {
      dispatch(addNotification({
        type: 'error',
        message: 'Failed to load user data. Please try logging in again.',
      }));
    }
  };

  const handle2FAError = (error: string) => {
    dispatch(addNotification({
      type: 'error',
      message: error,
    }));
  };

  const handle2FACancel = () => {
    setRequires2FA(false);
    setVerificationToken(null);
  };

  return (
    <div className="bg-theme-background min-h-screen relative overflow-hidden">
      {/* Decorative Background */}
      <div className="fixed inset-0 -z-10 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 -left-1/4 w-96 h-96 bg-theme-info/10 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 -right-1/4 w-96 h-96 bg-theme-interactive-primary/10 rounded-full blur-3xl" />
        <div className="absolute top-3/4 left-1/2 w-64 h-64 bg-theme-interactive-primary/5 rounded-full blur-2xl" />
      </div>

      <div className="relative flex flex-col justify-center py-12 px-4 sm:px-6 lg:px-8">
        <div className="sm:mx-auto sm:w-full sm:max-w-md">
          {/* Modern Logo and Title */}
          <div className="text-center">
            <Link to="/welcome" className="inline-block group">
              <div className="mx-auto w-16 h-16 rounded-2xl flex items-center justify-center mb-6 shadow-xl transition-all duration-200 group-hover:scale-105 border bg-gradient-to-br from-blue-600 to-purple-600 border-theme-info">
                <span className="text-white font-bold text-2xl">P</span>
              </div>
            </Link>
            <h1 className="text-3xl font-bold mb-2 text-theme-primary">
              Powernode
            </h1>
            <p className="font-medium text-theme-secondary">Welcome back to your dashboard</p>
          </div>
        </div>

        <div className="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
          <div className="py-8 px-4 sm:px-10 rounded-2xl border bg-theme-surface border-theme shadow-xl">

          {/* Show 2FA verification instead of login form when required */}
          {requires2FA && verificationToken ? (
            <TwoFactorVerification
              verificationToken={verificationToken}
              onSuccess={handle2FASuccess}
              onError={handle2FAError}
              onCancel={handle2FACancel}
            />
          ) : (
            <>
              {error && <ErrorAlert message={error} />}

              <DomainChangeNotice />

              <form className="space-y-6" onSubmit={handleSubmit}>
                <div>
                  <label htmlFor="email" className="block text-sm font-semibold mb-2 text-theme-primary">
                    Email address
                  </label>
                  <div className="form-field-icon relative">
                    <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none z-10">
                      <EnvelopeIcon className="h-5 w-5 text-theme-tertiary" />
                    </div>
                    <input
                      id="email"
                      name="email"
                      type="email"
                      autoComplete="username"
                      required
                      data-form-type="email"
                      data-testid="email-input"
                      className="input-theme block w-full rounded-xl border focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent transition-all duration-200"
                      placeholder="Enter your email address"
                      value={formData.email}
                      onChange={(e) => void handleChange(e)}
                    />
                  </div>
                  {touched.email && errors.email && (
                    <p className="mt-2 text-sm text-theme-danger">{errors.email}</p>
                  )}
                </div>

                <div>
                  <label htmlFor="password" className="block text-sm font-semibold mb-2 text-theme-primary">
                    Password
                  </label>
                  <div className="form-field-icon relative">
                    <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none z-10">
                      <LockClosedIcon className="h-5 w-5 text-theme-tertiary" />
                    </div>
                    <input
                      id="password"
                      name="password"
                      type={showPassword ? 'text' : 'password'}
                      autoComplete="current-password"
                      required
                      data-form-type="password"
                      data-testid="password-input"
                      className="input-theme block w-full pr-12 rounded-xl border focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent transition-all duration-200"
                      placeholder="Enter your password"
                      value={formData.password}
                      onChange={(e) => void handleChange(e)}
                    />
                    <button
                      type="button"
                      className="absolute inset-y-0 right-0 pr-3 flex items-center text-theme-tertiary hover:text-theme-secondary transition-colors duration-200 z-10"
                      onClick={() => setShowPassword(!showPassword)}
                      aria-label={showPassword ? "Hide password" : "Show password"}
                    >
                      {showPassword ? (
                        <EyeSlashIcon className="h-5 w-5" aria-hidden="true" />
                      ) : (
                        <EyeIcon className="h-5 w-5" aria-hidden="true" />
                      )}
                    </button>
                  </div>
                  {touched.password && errors.password && (
                    <p className="mt-2 text-sm text-theme-danger">{errors.password}</p>
                  )}
                </div>

                <div className="flex items-center justify-between">
                  <div className="flex items-center">
                    <input
                      id="remember-me"
                      name="remember-me"
                      type="checkbox"
                      checked={rememberMe}
                      onChange={(e) => setRememberMe(e.target.checked)}
                      data-testid="remember-me-checkbox"
                      className="checkbox-theme h-4 w-4 rounded transition-colors duration-200"
                    />
                    <label htmlFor="remember-me" className="ml-3 block text-sm font-medium text-theme-secondary">
                      Remember me for 30 days
                    </label>
                  </div>

                  <Link
                    to="/forgot-password"
                    data-testid="forgot-password-link"
                    className="text-sm font-semibold text-theme-link hover:text-theme-link transition-colors duration-200 hover:underline"
                  >
                    Forgot password?
                  </Link>
                </div>

                <div>
                  <button
                    type="submit"
                    disabled={loginLoading}
                    data-testid="login-submit-btn"
                    className="btn-theme btn-theme-primary btn-theme-lg w-full flex justify-center items-center py-3 px-4 border border-transparent rounded-xl text-sm font-semibold focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-200 transform hover:scale-105 shadow-lg hover:shadow-xl"
                  >
                    {loginLoading ? (
                      <div className="flex items-center">
                        <div className="animate-spin -ml-1 mr-3 h-5 w-5 border-2 border-white border-t-transparent rounded-full" />
                        <span>Signing in...</span>
                      </div>
                    ) : (
                      <div className="flex items-center space-x-2">
                        <span>Sign in to Dashboard</span>
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 8l4 4m0 0l-4 4m4-4H3" />
                        </svg>
                      </div>
                    )}
                  </button>
                </div>
          </form>

            {/* Modern Divider */}
            <div className="mt-8">
              <div className="relative">
                <div className="absolute inset-0 flex items-center">
                  <div className="w-full border-t border-theme" />
                </div>
                <div className="relative flex justify-center text-sm">
                  <span className="px-4 font-medium bg-theme-surface text-theme-secondary">
                    New to Powernode?
                  </span>
                </div>
              </div>
            </div>

            <div className="mt-6 text-center">
              <Link
                to="/plans"
                className="btn-theme btn-theme-secondary w-full inline-flex justify-center items-center space-x-2 py-3 px-4 border border-theme rounded-xl text-sm font-semibold transition-all duration-200 shadow-md hover:shadow-lg"
              >
                <span>Create your account</span>
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
              </Link>
            </div>
            
            {/* Enhanced Trust Indicators */}
            <div className="mt-8 flex flex-wrap items-center justify-center gap-6 text-xs text-theme-tertiary">
              <div className="flex items-center space-x-2">
                <div className="w-4 h-4 rounded-full flex items-center justify-center bg-theme-success">
                  <svg className="w-2.5 h-2.5 text-white" fill="currentColor" viewBox="0 0 20 20">
                    <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                  </svg>
                </div>
                <span className="font-medium">Secure Login</span>
              </div>
              <div className="flex items-center space-x-2">
                <div className="w-4 h-4 rounded-full flex items-center justify-center bg-theme-info">
                  <svg className="w-2.5 h-2.5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                  </svg>
                </div>
                <span className="font-medium">256-bit SSL</span>
              </div>
              <div className="flex items-center space-x-2">
                <div className="w-4 h-4 rounded-full flex items-center justify-center bg-theme-interactive-primary">
                  <span className="text-white text-xs font-bold">2FA</span>
                </div>
                <span className="font-medium">Two-Factor Auth</span>
              </div>
            </div>
          </>
          )}
          </div>
        </div>
        
        {/* Modern Footer */}
        <div className="mt-12 text-center">
          <div className="flex flex-wrap items-center justify-center gap-6 mb-4">
            <Link to="/privacy" className="text-xs text-theme-tertiary hover:text-theme-secondary transition-colors duration-200 hover:underline">
              Privacy Policy
            </Link>
            <Link to="/terms" className="text-xs text-theme-tertiary hover:text-theme-secondary transition-colors duration-200 hover:underline">
              Terms of Service
            </Link>
            <Link to="/support" className="text-xs text-theme-tertiary hover:text-theme-secondary transition-colors duration-200 hover:underline">
              Support
            </Link>
          </div>
          <p className="text-xs text-theme-tertiary">
            {copyrightText || `© ${new Date().getFullYear()} Everett C. Haimes III. All rights reserved.`}
          </p>
        </div>
      </div>
    </div>
  );
};
