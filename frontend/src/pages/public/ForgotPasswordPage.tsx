import React, { useState } from 'react';

import { Link } from 'react-router-dom';

import { authApi } from '@/features/account/auth/services/authAPI';
import { ErrorHandler } from '@/shared/utils/errorHandling';

import { useDispatch } from 'react-redux';

import { AppDispatch } from '@/shared/services';

import { addNotification } from '@/shared/services/slices/uiSlice';


export const ForgotPasswordPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const [email, setEmail] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isSubmitted, setIsSubmitted] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);

    try {
      await authApi.forgotPassword(email);
      setIsSubmitted(true);
      dispatch(addNotification({
        type: 'success',
        message: 'Password reset email sent. Check your inbox.',
      }));
    } catch (error: unknown) {
      dispatch(addNotification({
        type: 'error',
        message: ErrorHandler.getUserMessage(error),
      }));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-theme-background-secondary py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md w-full space-y-8">
        <div>
          <Link to="/welcome" className="inline-block mx-auto">
            <div className="mx-auto h-12 w-12 flex items-center justify-center rounded-xl bg-theme-interactive-primary hover:shadow-lg transition-all duration-200 hover:scale-105">
              <span className="text-white font-bold text-xl">P</span>
            </div>
          </Link>
          <h2 className="mt-6 text-center text-3xl font-extrabold text-theme-primary">
            Reset your password
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

        {isSubmitted ? (
          <div className="alert-theme alert-theme-success rounded-md p-4">
            <div className="flex">
              <div className="ml-3">
                <h3 className="text-sm font-medium">
                  Email sent!
                </h3>
                <div className="mt-2 text-sm">
                  <p>
                    We've sent a password reset link to <strong>{email}</strong>.
                    Please check your email and follow the instructions to reset your password.
                  </p>
                </div>
              </div>
            </div>
          </div>
        ) : (
          <form className="mt-8 space-y-6" onSubmit={handleSubmit}>
            <div>
              <label htmlFor="email" className="label-theme">
                Email address
              </label>
              <input
                id="email"
                name="email"
                type="email"
                autoComplete="email"
                required
                className="input-theme mt-1 block w-full"
                placeholder="Enter your email address"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
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
                    Sending email...
                  </div>
                ) : (
                  'Send reset email'
                )}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
};
