import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useDispatch, useSelector } from 'react-redux';
import { RootState, AppDispatch } from '../../store';
import { register, clearError } from '../../store/slices/authSlice';
import { addNotification } from '../../store/slices/uiSlice';

export const RegisterPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const navigate = useNavigate();
  
  const { isLoading, error } = useSelector((state: RootState) => state.auth);
  
  const [formData, setFormData] = useState({
    email: '',
    password: '',
    firstName: '',
    lastName: '',
    accountName: '',
  });

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
    
    if (error) {
      dispatch(clearError());
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    try {
      await dispatch(register(formData)).unwrap();
      dispatch(addNotification({
        type: 'success',
        message: 'Registration successful! Welcome to Powernode.',
      }));
      navigate('/dashboard', { replace: true });
    } catch (error: any) {
      dispatch(addNotification({
        type: 'error',
        message: error.message || 'Registration failed. Please try again.',
      }));
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-theme-background py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md w-full space-y-8">
        <div>
          <div className="mx-auto h-12 w-12 flex items-center justify-center rounded-xl bg-theme-interactive-primary">
            <span className="text-white font-bold text-xl">P</span>
          </div>
          <h2 className="mt-6 text-center text-3xl font-extrabold text-theme-primary">
            Create your account
          </h2>
          <p className="mt-2 text-center text-sm text-theme-secondary">
            Already have an account?{' '}
            <Link
              to="/login"
              className="font-medium text-theme-link hover:text-theme-link-hover"
            >
              Sign in
            </Link>
          </p>
        </div>

        <form className="mt-8 space-y-4" onSubmit={handleSubmit}>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label htmlFor="firstName" className="label-theme">
                First Name
              </label>
              <input
                id="firstName"
                name="firstName"
                type="text"
                required
                className="input-theme mt-1 block w-full"
                value={formData.firstName}
                onChange={handleChange}
              />
            </div>
            <div>
              <label htmlFor="lastName" className="label-theme">
                Last Name
              </label>
              <input
                id="lastName"
                name="lastName"
                type="text"
                required
                className="input-theme mt-1 block w-full"
                value={formData.lastName}
                onChange={handleChange}
              />
            </div>
          </div>

          <div>
            <label htmlFor="accountName" className="label-theme">
              Company Name
            </label>
            <input
              id="accountName"
              name="accountName"
              type="text"
              required
              className="input-theme mt-1 block w-full"
              placeholder="Your company name"
              value={formData.accountName}
              onChange={handleChange}
            />
          </div>

          <div>
            <label htmlFor="email" className="label-theme">
              Email Address
            </label>
            <input
              id="email"
              name="email"
              type="email"
              autoComplete="email"
              required
              className="input-theme mt-1 block w-full"
              value={formData.email}
              onChange={handleChange}
            />
          </div>

          <div>
            <label htmlFor="password" className="label-theme">
              Password
            </label>
            <input
              id="password"
              name="password"
              type="password"
              autoComplete="new-password"
              required
              className="input-theme mt-1 block w-full"
              value={formData.password}
              onChange={handleChange}
            />
          </div>

          <div>
            <button
              type="submit"
              disabled={isLoading}
              className="btn-theme btn-theme-primary w-full justify-center"
            >
              {isLoading ? (
                <div className="flex items-center">
                  <div className="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full mr-2" />
                  Creating account...
                </div>
              ) : (
                'Create account'
              )}
            </button>
          </div>

          {error && (
            <div className="alert-theme alert-theme-error">
              <div className="text-sm">{error}</div>
            </div>
          )}
        </form>
      </div>
    </div>
  );
};