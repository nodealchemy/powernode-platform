import React, { useState, useEffect } from 'react';
import { Link, useNavigate, useLocation } from 'react-router-dom';
import { useDispatch, useSelector } from 'react-redux';
import { RootState, AppDispatch } from '../../store';
import { login, clearError } from '../../store/slices/authSlice';
import { addNotification } from '../../store/slices/uiSlice';
import { EyeIcon, EyeSlashIcon, LockClosedIcon, EnvelopeIcon } from '@heroicons/react/24/outline';

export const LoginPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const navigate = useNavigate();
  const location = useLocation();
  
  const { isLoading, error } = useSelector((state: RootState) => state.auth);
  
  const [formData, setFormData] = useState({
    email: '',
    password: '',
  });
  
  const [showPassword, setShowPassword] = useState(false);
  const [rememberMe, setRememberMe] = useState(false);
  
  // Clear error when component unmounts or user navigates away
  useEffect(() => {
    return () => {
      dispatch(clearError());
    };
  }, [dispatch]);

  const from = (location.state as any)?.from?.pathname || '/dashboard';

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
    
    try {
      await dispatch(login(formData)).unwrap();
      dispatch(addNotification({
        type: 'success',
        message: 'Login successful! Welcome back.',
      }));
      navigate(from, { replace: true });
    } catch (error: any) {
      dispatch(addNotification({
        type: 'error',
        message: error.message || 'Login failed. Please try again.',
      }));
    }
  };

  return (
    <div className="min-h-screen bg-theme-background-secondary flex flex-col justify-center py-12 px-4 sm:px-6 lg:px-8">
      <div className="sm:mx-auto sm:w-full sm:max-w-md">
        {/* Logo and Title */}
        <div className="text-center">
          <div className="mx-auto w-16 h-16 bg-theme-interactive-primary rounded-2xl flex items-center justify-center mb-6 shadow-lg">
            <span className="text-white font-bold text-2xl">P</span>
          </div>
          <h1 className="text-3xl font-bold text-theme-primary mb-2">Powernode</h1>
          <p className="text-theme-secondary">Welcome back</p>
        </div>
      </div>

      <div className="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div className="bg-theme-surface py-8 px-4 shadow-xl border border-theme sm:rounded-xl sm:px-10">

          {error && (
            <div className="mb-6 bg-theme-error border border-theme text-theme-error px-4 py-3 rounded-lg">
              <div className="flex">
                <div className="ml-3">
                  <p className="text-sm font-medium">{error}</p>
                </div>
              </div>
            </div>
          )}

          <form className="space-y-6" onSubmit={handleSubmit}>
            <div>
              <label htmlFor="email" className="label-theme">
                Email address
              </label>
              <div className="form-field-icon">
                <EnvelopeIcon className="form-icon" />
                <input
                  id="email"
                  name="email"
                  type="email"
                  autoComplete="email"
                  required
                  className="input-theme"
                  placeholder="Enter your email"
                  value={formData.email}
                  onChange={handleChange}
                />
              </div>
            </div>

            <div>
              <label htmlFor="password" className="label-theme">
                Password
              </label>
              <div className="form-field-icon">
                <LockClosedIcon className="form-icon" />
                <input
                  id="password"
                  name="password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  required
                  className="input-theme pr-12"
                  placeholder="Enter your password"
                  value={formData.password}
                  onChange={handleChange}
                />
                <button
                  type="button"
                  className="absolute inset-y-0 right-0 pr-3 flex items-center text-theme-tertiary hover:text-theme-secondary transition-colors"
                  onClick={() => setShowPassword(!showPassword)}
                >
                  {showPassword ? (
                    <EyeSlashIcon className="h-5 w-5" />
                  ) : (
                    <EyeIcon className="h-5 w-5" />
                  )}
                </button>
              </div>
            </div>

            <div className="flex items-center justify-between">
              <div className="flex items-center">
                <input
                  id="remember-me"
                  name="remember-me"
                  type="checkbox"
                  checked={rememberMe}
                  onChange={(e) => setRememberMe(e.target.checked)}
                  className="checkbox-theme"
                />
                <label htmlFor="remember-me" className="ml-2 block text-sm text-theme-secondary">
                  Remember me
                </label>
              </div>

              <Link
                to="/forgot-password"
                className="text-sm font-medium text-theme-link hover:text-theme-link-hover transition-colors"
              >
                Forgot your password?
              </Link>
            </div>

            <div>
              <button
                type="submit"
                disabled={isLoading}
                className="btn-theme btn-theme-primary w-full py-3"
              >
                {isLoading ? (
                  <div className="flex items-center">
                    <div className="animate-spin -ml-1 mr-3 h-5 w-5 border-2 border-white border-t-transparent rounded-full" />
                    Signing in...
                  </div>
                ) : (
                  'Sign in'
                )}
              </button>
            </div>
          </form>

          {/* Divider */}
          <div className="mt-8">
            <div className="relative">
              <div className="absolute inset-0 flex items-center">
                <div className="w-full border-t border-theme" />
              </div>
              <div className="relative flex justify-center text-sm">
                <span className="px-2 bg-theme-surface text-theme-tertiary">New to Powernode?</span>
              </div>
            </div>
          </div>

          <div className="mt-6 text-center">
            <Link
              to="/plans"
              className="btn-theme btn-theme-secondary w-full py-2.5"
            >
              Create your account
            </Link>
          </div>
          
          {/* Trust indicators */}
          <div className="mt-6 text-center">
            <p className="text-xs text-theme-tertiary">
              Secure login • 256-bit SSL encryption
            </p>
          </div>
        </div>
      </div>
      
      {/* Footer */}
      <div className="mt-8 text-center">
        <p className="text-xs text-theme-tertiary">
          © 2024 Powernode. All rights reserved.
        </p>
      </div>
    </div>
  );
};