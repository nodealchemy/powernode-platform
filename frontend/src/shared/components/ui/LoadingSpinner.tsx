import React from 'react';

export interface LoadingSpinnerProps {
  size?: 'sm' | 'md' | 'lg' | 'xl';
  className?: string;
  message?: string;
  showAuthFallback?: boolean;
  onAuthFallback?: () => void;
}

export const LoadingSpinner: React.FC<LoadingSpinnerProps> = ({
LoadingSpinner.displayName = 'LoadingSpinner';
  size = 'md',
  className = '',
  message,
  showAuthFallback = false,
  onAuthFallback
}) => {
  const sizeClasses = {
    sm: 'h-4 w-4',
    md: 'h-8 w-8',
    lg: 'h-12 w-12',
    xl: 'h-16 w-16'
  };

  // eslint-disable-next-line security/detect-object-injection
  const selectedSizeClasses = sizeClasses[size] || sizeClasses.md;
  
  return (
    <div className={`flex flex-col items-center justify-center space-y-4 ${className}`}>
      <div className="relative">
        <div className={`animate-spin rounded-full border-2 border-theme-tertiary border-t-theme-interactive-primary ${selectedSizeClasses}`} />
      </div>
      
      {message && (
        <div className="text-center">
          <p className="text-theme-secondary text-sm">{message}</p>
        </div>
      )}
      
      {showAuthFallback && onAuthFallback && (
        <button
          onClick={onAuthFallback}
          className="text-theme-interactive-primary hover:text-theme-interactive-primary-hover text-sm underline transition-colors duration-200"
        >
          Continue without loading
        </button>
      )}
    </div>
  );
};

export default LoadingSpinner;