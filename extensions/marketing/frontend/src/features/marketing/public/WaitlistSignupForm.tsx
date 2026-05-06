import React, { useState } from 'react';
import { ArrowRight, Check } from 'lucide-react';

import { leadsApi } from '../services/leadsApi';

interface WaitlistSignupFormProps {
  source?: string;
}

export const WaitlistSignupForm: React.FC<WaitlistSignupFormProps> = ({ source = 'homepage' }) => {
  const [email, setEmail] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [success, setSuccess] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setSuccess(null);

    if (!email || !email.includes('@')) {
      setError('Please enter a valid email address');
      return;
    }

    setSubmitting(true);
    try {
      const params = new URLSearchParams(window.location.search);
      const response = await leadsApi.submitWaitlist({
        source,
        email,
        utm_source: params.get('utm_source') ?? undefined,
        utm_medium: params.get('utm_medium') ?? undefined,
        utm_campaign: params.get('utm_campaign') ?? undefined,
        utm_term: params.get('utm_term') ?? undefined,
        utm_content: params.get('utm_content') ?? undefined,
      });
      setSuccess(response.message ?? "You're on the waitlist!");
      setEmail('');
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Could not subscribe. Please try again.';
      setError(message);
    } finally {
      setSubmitting(false);
    }
  };

  if (success) {
    return (
      <div
        className="max-w-md mx-auto p-6 bg-theme-success/10 rounded-2xl border border-theme-success-solid text-center"
        data-testid="waitlist-success"
      >
        <div className="w-12 h-12 mx-auto mb-3 rounded-full bg-theme-success-solid flex items-center justify-center">
          <Check className="w-6 h-6 text-white" />
        </div>
        <p className="text-theme-primary font-semibold">{success}</p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="max-w-md mx-auto" data-testid="waitlist-form">
      <div className="flex flex-col sm:flex-row gap-3">
        <input
          type="email"
          value={email}
          onChange={e => setEmail(e.target.value)}
          placeholder="you@example.com"
          required
          disabled={submitting}
          aria-label="Email address"
          className="flex-1 px-4 py-3 rounded-xl bg-theme-background border border-theme text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-info-solid disabled:opacity-50"
          data-testid="waitlist-email-input"
        />
        <button
          type="submit"
          disabled={submitting || !email}
          className="inline-flex items-center justify-center space-x-2 px-6 py-3 bg-theme-info-solid hover:bg-theme-interactive-primary-hover text-white font-semibold rounded-xl transition-all duration-200 shadow-lg hover:shadow-xl disabled:opacity-50 disabled:cursor-not-allowed"
          data-testid="waitlist-submit"
        >
          <span>{submitting ? 'Joining…' : 'Join Waitlist'}</span>
          {!submitting && <ArrowRight className="w-4 h-4" />}
        </button>
      </div>
      {error && (
        <p className="mt-3 text-sm text-theme-danger-solid text-center" data-testid="waitlist-error">
          {error}
        </p>
      )}
    </form>
  );
};
