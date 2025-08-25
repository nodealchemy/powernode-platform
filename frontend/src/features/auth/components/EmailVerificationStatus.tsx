import React from 'react';
import { CheckCircle, AlertTriangle, Clock } from 'lucide-react';

interface EmailVerificationStatusProps {
  isVerified: boolean;
  showIcon?: boolean;
  showText?: boolean;
  size?: 'sm' | 'md' | 'lg';
  variant?: 'badge' | 'inline' | 'tooltip';
}

export const EmailVerificationStatus: React.FC<EmailVerificationStatusProps> = ({
  isVerified,
  showIcon = true,
  showText = true,
  size = 'md',
  variant = 'inline'
}) => {
  const sizeClasses = {
    sm: {
      icon: 'h-3 w-3',
      text: 'text-xs',
      badge: 'px-2 py-1 text-xs'
    },
    md: {
      icon: 'h-4 w-4',
      text: 'text-sm',
      badge: 'px-2.5 py-1.5 text-sm'
    },
    lg: {
      icon: 'h-5 w-5',
      text: 'text-base',
      badge: 'px-3 py-2 text-base'
    }
  };

  const iconClass = sizeClasses[size].icon;
  const textClass = sizeClasses[size].text;
  const badgeClass = sizeClasses[size].badge;

  const Icon = isVerified ? CheckCircle : AlertTriangle;
  const iconColor = isVerified ? 'text-theme-success' : 'text-theme-warning';
  const textColor = isVerified ? 'text-theme-success' : 'text-theme-warning';
  const statusText = isVerified ? 'Verified' : 'Unverified';

  if (variant === 'badge') {
    return (
      <span
        className={`inline-flex items-center rounded-full font-medium ${badgeClass} ${
          isVerified 
            ? 'bg-theme-success-subtle text-theme-success' 
            : 'bg-theme-warning-subtle text-theme-warning'
        }`}
      >
        {showIcon && <Icon className={`${iconClass} mr-1`} />}
        {showText && statusText}
      </span>
    );
  }

  if (variant === 'tooltip') {
    return (
      <div className="group relative">
        {showIcon && <Icon className={`${iconClass} ${iconColor}`} />}
        <div className="absolute bottom-full left-1/2 transform -translate-x-1/2 mb-2 px-2 py-1 bg-theme-surface-dark text-white text-xs rounded opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap z-10">
          Email {statusText}
          <div className="absolute top-full left-1/2 transform -translate-x-1/2 border-4 border-transparent border-t-theme-surface-dark"></div>
        </div>
      </div>
    );
  }

  // Default inline variant
  return (
    <div className="inline-flex items-center">
      {showIcon && <Icon className={`${iconClass} ${iconColor} mr-1.5`} />}
      {showText && (
        <span className={`${textClass} ${textColor} font-medium`}>
          {statusText}
        </span>
      )}
    </div>
  );
};

// Convenience component for showing verification status with loading state
export const EmailVerificationLoader: React.FC<{ 
  size?: 'sm' | 'md' | 'lg';
  showText?: boolean;
}> = ({ size = 'md', showText = true }) => {
  const iconClass = size === 'sm' ? 'h-3 w-3' : size === 'lg' ? 'h-5 w-5' : 'h-4 w-4';
  const textClass = size === 'sm' ? 'text-xs' : size === 'lg' ? 'text-base' : 'text-sm';

  return (
    <div className="inline-flex items-center">
      <Clock className={`${iconClass} text-theme-muted animate-spin mr-1.5`} />
      {showText && (
        <span className={`${textClass} text-theme-muted`}>
          Checking...
        </span>
      )}
    </div>
  );
};

export default EmailVerificationStatus;