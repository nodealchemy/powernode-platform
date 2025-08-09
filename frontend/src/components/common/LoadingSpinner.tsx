import React from 'react';

interface LoadingSpinnerProps {
  size?: 'small' | 'medium' | 'large';
  message?: string;
  showAuthFallback?: boolean;
  onAuthFallback?: () => void;
}

export const LoadingSpinner: React.FC<LoadingSpinnerProps> = ({
  size = 'medium',
  message = 'Loading...',
  showAuthFallback = false,
  onAuthFallback,
}) => {
  const sizeClasses = {
    small: 'h-4 w-4',
    medium: 'h-8 w-8',
    large: 'h-12 w-12',
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-theme-background">
      <div
        className={`animate-spin rounded-full border-4 border-theme border-t-blue-600 ${
          size === 'small' ? sizeClasses.small :
          size === 'large' ? sizeClasses.large :
          sizeClasses.medium
        }`}
      />
      {message && (
        <p className="mt-4 text-theme-secondary text-sm font-medium">{message}</p>
      )}
      {showAuthFallback && onAuthFallback && (
        <button
          onClick={onAuthFallback}
          className="mt-6 px-4 py-2 btn-theme-primary rounded-md transition-colors text-sm font-medium"
        >
          Go to Login
        </button>
      )}
    </div>
  );
};