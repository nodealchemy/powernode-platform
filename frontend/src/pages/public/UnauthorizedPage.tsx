import React from 'react';
import { Link } from 'react-router-dom';

export const UnauthorizedPage: React.FC = () => {
  return (
    <div className="min-h-screen flex items-center justify-center bg-theme-background-secondary">
      <div className="text-center">
        <div className="mx-auto h-12 w-12 flex items-center justify-center rounded-xl bg-theme-background-tertiary">
          <svg className="h-6 w-6 text-theme-danger" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.732-.833-2.464 0L4.35 16.5c-.77.833.192 2.5 1.732 2.5z" />
          </svg>
        </div>
        <h1 className="mt-6 text-4xl font-bold text-theme-primary">403</h1>
        <h2 className="mt-2 text-xl font-semibold text-theme-secondary">
          Access Denied
        </h2>
        <p className="mt-2 text-theme-tertiary">
          You don't have permission to access this resource.
        </p>
        <div className="mt-6">
          <Link
            to="/dashboard"
            className="btn-theme btn-theme-primary inline-flex items-center"
          >
            Go to Dashboard
          </Link>
        </div>
      </div>
    </div>
  );
};