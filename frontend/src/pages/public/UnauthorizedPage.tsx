import React from 'react';
import { Link } from 'react-router-dom';
import { ShieldExclamationIcon, HomeIcon, ArrowLeftIcon } from '@heroicons/react/24/outline';

export const UnauthorizedPage: React.FC = () => {
  return (
    <div className="min-h-screen flex items-center justify-center bg-theme-background-secondary relative overflow-hidden">
      {/* Decorative Background */}
      <div className="fixed inset-0 -z-10 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 -left-1/4 w-96 h-96 bg-theme-danger/5 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 -right-1/4 w-96 h-96 bg-theme-warning/5 rounded-full blur-3xl" />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-64 h-64 bg-theme-warning/5 rounded-full blur-2xl" />
      </div>

      <div className="text-center max-w-md mx-auto px-4">
        {/* Icon */}
        <div className="mx-auto h-20 w-20 flex items-center justify-center rounded-2xl bg-theme-danger/10 border border-theme-danger/20 mb-8">
          <ShieldExclamationIcon className="h-10 w-10 text-theme-danger" />
        </div>

        {/* Error Code */}
        <h1 className="text-7xl font-bold text-theme-primary mb-4">403</h1>

        {/* Title */}
        <h2 className="text-2xl font-semibold text-theme-secondary mb-4">
          Access Denied
        </h2>

        {/* Description */}
        <p className="text-theme-tertiary mb-8 leading-relaxed">
          You don't have permission to access this resource. This might be because your account doesn't have the required permissions, or the resource is restricted.
        </p>

        {/* Action Buttons */}
        <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
          <Link
            to="/dashboard"
            className="btn-theme btn-theme-primary inline-flex items-center gap-2 px-6 py-3 rounded-xl"
          >
            <HomeIcon className="h-5 w-5" />
            Go to Dashboard
          </Link>
          <button
            onClick={() => window.history.back()}
            className="btn-theme btn-theme-secondary inline-flex items-center gap-2 px-6 py-3 rounded-xl"
          >
            <ArrowLeftIcon className="h-5 w-5" />
            Go Back
          </button>
        </div>

        {/* Help Text */}
        <p className="mt-8 text-sm text-theme-tertiary">
          Need access?{' '}
          <Link to="/pages/contact" className="text-theme-link hover:text-theme-link-hover underline">
            Contact your administrator
          </Link>{' '}
          or{' '}
          <Link to="/pages/help" className="text-theme-link hover:text-theme-link-hover underline">
            visit our Help Center
          </Link>
        </p>
      </div>
    </div>
  );
};
