import React, { useState } from 'react';

import { useParams, useNavigate, Link } from 'react-router-dom';

import { authApi } from '@/features/account/auth/services/authAPI';

import { useDispatch } from 'react-redux';

import { AppDispatch } from '@/shared/services';

import { addNotification } from '@/shared/services/slices/uiSlice';

import { getErrorMessage } from '@/shared/utils/errorHandling';


export const ResetPasswordPage: React.FC = () => {
  const { token } = useParams<{ token: string }>();
  const navigate = useNavigate();
  const dispatch = useDispatch<AppDispatch>();
  
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    // eslint-disable-next-line security/detect-possible-timing-attacks
    if (password !== confirmPassword) {
      dispatch(addNotification({
        type: 'error',
        message: 'Passwords do not match.',
      }));
      return;
    }

    if (!token) {
      dispatch(addNotification({
        type: 'error',
        message: 'Invalid reset token.',
      }));
      return;
    }

    setIsLoading(true);

    try {
      await authApi.resetPassword(token, password);
      dispatch(addNotification({
        type: 'success',
        message: 'Password reset successful. You can now sign in.',
      }));
      navigate('/login');
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error),
      }));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-theme-background py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md w-full space-y-8">
        <div>
          <Link to="/welcome" className="inline-block mx-auto">
            <div className="mx-auto h-12 w-12 flex items-center justify-center rounded-xl bg-theme-interactive-primary hover:shadow-lg transition-all duration-200 hover:scale-105">
              <span className="text-white font-bold text-xl">P</span>
            </div>
          </Link>
          <h2 className="mt-6 text-center text-3xl font-extrabold text-theme-primary">
            Set new password
          </h2>
          <p className="mt-2 text-center text-sm text-theme-secondary">
            Remember your password?{' '}
            <Link
              to="/login"
              className="font-medium text-theme-link hover:text-theme-link-hover"
            >
              Sign in
            </Link>
          </p>
        </div>

        <form className="mt-8 space-y-6" onSubmit={handleSubmit}>
          <div>
            <label htmlFor="password" className="label-theme">
              New Password
            </label>
            <input
              id="password"
              name="password"
              type="password"
              autoComplete="new-password"
              required
              className="input-theme mt-1 block w-full"
              placeholder="Enter new password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>

          <div>
            <label htmlFor="confirmPassword" className="label-theme">
              Confirm Password
            </label>
            <input
              id="confirmPassword"
              name="confirmPassword"
              type="password"
              autoComplete="new-password"
              required
              className="input-theme mt-1 block w-full"
              placeholder="Confirm new password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
            />
          </div>

          <div>
            <button
              type="submit"
              disabled={isLoading}
              className="btn-theme btn-theme-primary w-full justify-center disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isLoading ? (
                <div className="flex items-center">
                  <div className="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full mr-2" />
                  Updating password...
                </div>
              ) : (
                'Update password'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
