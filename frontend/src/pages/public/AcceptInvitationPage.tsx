import React, { useState, useEffect, useCallback } from 'react';

import { useParams, useNavigate, Link } from 'react-router-dom';

import { invitationsApi, Invitation } from '@/shared/services/account/invitationsApi';

import { FormField } from '@/shared/components/ui/FormField';

import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';


export const AcceptInvitationPage: React.FC = () => {
  const { token } = useParams<{ token: string }>();
  const navigate = useNavigate();
  
  const [invitation, setInvitation] = useState<Invitation | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const submitting = isSubmitting;
  const [error, setError] = useState<string | null>(null);
  const [formData, setFormData] = useState({
    first_name: '',
    last_name: '',
    password: '',
    password_confirmation: ''
  });
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});

  const loadInvitation = useCallback(async () => {
    if (!token) return;
    
    try {
      setIsLoading(true);
      const response = await invitationsApi.getInvitationByToken(token);
      
      if (response.success) {
        setInvitation(response.data);
        if (response.data.status !== 'pending') {
          setError(`This invitation has been ${response.data.status}`);
        }
      } else {
        setError(response.message || 'Invitation not found or expired');
      }
    } catch (_err) {
      setError('Failed to load invitation details');
    } finally {
      setIsLoading(false);
    }
  }, [token]);

  useEffect(() => {

    if (!token) {
      setError('Invalid invitation link');
      setIsLoading(false);
      return;
    }
    
 void loadInvitation();
  }, [token, loadInvitation]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !invitation) return;
    
    setIsSubmitting(true);
    setFormErrors({});

    try {
      // Validate form
      const newErrors: Record<string, string> = {};
      
      if (!formData.first_name.trim()) {
        newErrors.first_name = 'First name is required';
      }
      
      if (!formData.last_name.trim()) {
        newErrors.last_name = 'Last name is required';
      }
      
      if (!formData.password) {
        newErrors.password = 'Password is required';
      } else if (formData.password.length < 12) {
        newErrors.password = 'Password must be at least 12 characters';
      } else if (!/(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])/.test(formData.password)) {
        newErrors.password = 'Password must contain uppercase, lowercase, number, and special character';
      }
      
      if (formData.password !== formData.password_confirmation) {
        newErrors.password_confirmation = 'Passwords do not match';
      }

      if (Object.keys(newErrors).length > 0) {
        setFormErrors(newErrors);
        return;
      }

      // Accept invitation
      const response = await invitationsApi.acceptInvitation(token, formData);
      
      if (response.success) {
        // Redirect to login with success message
        navigate('/login', { 
          state: { 
            message: 'Account created successfully! Please sign in to continue.',
            type: 'success'
          } 
        });
      } else {
        setError(response.message || 'Failed to accept invitation');
        if (response.errors) {
          const errorMap: Record<string, string> = {};
          response.errors.forEach(err => {
            const [field, message] = err.split(': ');
            if (field && message) {
              errorMap[field as keyof typeof errorMap] = message;
            }
          });
          setFormErrors(errorMap);
        }
      }
    } catch (_err) {
      setError('An unexpected error occurred');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleInputChange = (field: keyof typeof formData, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    if (formErrors[field as keyof typeof formErrors]) {
      setFormErrors(prev => ({ ...prev, [field]: '' }));
    }
  };

  if (isLoading) {
    return <LoadingSpinner message="Loading invitation..." />;
  }

  if (error || !invitation) {
    return (
      <div className="min-h-screen bg-theme-background flex items-center justify-center px-4">
        <div className="max-w-md w-full">
          <div className="bg-theme-surface rounded-lg shadow-sm p-8 text-center">
            <div className="text-6xl mb-4">❌</div>
            <h1 className="text-2xl font-bold text-theme-primary mb-4">
              Invalid Invitation
            </h1>
            <p className="text-theme-secondary mb-8">
              {error || 'This invitation link is invalid or has expired.'}
            </p>
            <Link
              to="/login"
              className="btn-theme btn-theme-primary w-full"
            >
              Go to Login
            </Link>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-theme-background flex items-center justify-center px-4">
      <div className="max-w-md w-full">
        <div className="bg-theme-surface rounded-lg shadow-sm p-8">
          {/* Header */}
          <div className="text-center mb-8">
            <div className="text-4xl mb-4">🎉</div>
            <h1 className="text-2xl font-bold text-theme-primary mb-2">
              Join the Team!
            </h1>
            <p className="text-theme-secondary">
              You've been invited to join <strong className="text-theme-primary">Powernode</strong>
            </p>
          </div>

          {/* Invitation Details */}
          <div className="bg-theme-background rounded-lg p-4 mb-6">
            <div className="text-center">
              <p className="text-sm text-theme-secondary mb-1">You're being invited as:</p>
              <span className="inline-block bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary px-3 py-1 rounded-full text-sm font-medium">
                {invitation.role.charAt(0).toUpperCase() + invitation.role.slice(1)}
              </span>
            </div>
          </div>

          {/* Form */}
          <form onSubmit={handleSubmit} className="space-y-6">
            {error && (
              <div className="bg-theme-error bg-opacity-10 border border-theme-error text-theme-error p-4 rounded-lg text-sm">
                {error}
              </div>
            )}

            <div className="grid grid-cols-2 gap-4">
              <FormField
                label="First Name"
                type="text"
                value={formData.first_name}
                onChange={(value) => handleInputChange('first_name', value)}
                error={formErrors.first_name}
                required
                placeholder="John"
              />
              <FormField
                label="Last Name"
                type="text"
                value={formData.last_name}
                onChange={(value) => handleInputChange('last_name', value)}
                error={formErrors.last_name}
                required
                placeholder="Doe"
              />
            </div>

            <FormField
              label="Password"
              type="password"
              value={formData.password}
              onChange={(value) => handleInputChange('password', value)}
              error={formErrors.password}
              required
              placeholder="Create a strong password"
            />

            <FormField
              label="Confirm Password"
              type="password"
              value={formData.password_confirmation}
              onChange={(value) => handleInputChange('password_confirmation', value)}
              error={formErrors.password_confirmation}
              required
              placeholder="Confirm your password"
            />

            <div className="bg-theme-background p-4 rounded-lg">
              <h4 className="font-medium text-theme-primary mb-2">Password Requirements</h4>
              <ul className="text-sm text-theme-secondary space-y-1">
                <li>• At least 12 characters long</li>
                <li>• Contains uppercase and lowercase letters</li>
                <li>• Contains at least one number</li>
                <li>• Contains at least one special character (@$!%*?&)</li>
              </ul>
            </div>

            <button
              type="submit"
              disabled={submitting}
              className="w-full btn-theme btn-theme-primary"
            >
              {isSubmitting ? (
                <>
                  <div className="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full mr-2"></div>
                  Creating Account...
                </>
              ) : (
                'Accept Invitation & Create Account'
              )}
            </button>
          </form>

          {/* Footer */}
          <div className="mt-8 text-center">
            <p className="text-sm text-theme-secondary">
              Already have an account?{' '}
              <Link to="/login" className="text-theme-link hover:text-theme-link-hover">
                Sign in instead
              </Link>
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default AcceptInvitationPage;
