import React from 'react';

export interface BadgeProps {
  children: React.ReactNode;
  variant?: 'default' | 'primary' | 'secondary' | 'success' | 'warning' | 'danger' | 'info' | 'outline';
  size?: 'xs' | 'sm' | 'md' | 'lg';
  className?: string;
  dot?: boolean;
  pulse?: boolean;
  icon?: React.ReactNode;
  removable?: boolean;
  onRemove?: () => void;
  rounded?: 'md' | 'lg' | 'full';
}

export const Badge: React.FC<BadgeProps> = ({
Badge.displayName = 'Badge';
  children,
  variant = 'default',
  size = 'sm',
  className = '',
  dot = false,
  pulse = false,
  icon,
  removable = false,
  onRemove,
  rounded = 'full'
}) => {
  // Base theme classes
  const baseClasses = 'badge-theme';
  
  // Theme variant classes
  const variantClasses = {
    default: 'badge-theme-default',
    primary: 'badge-theme-primary',
    secondary: 'badge-theme-secondary',
    success: 'badge-theme-success',
    warning: 'badge-theme-warning',
    danger: 'badge-theme-danger',
    info: 'badge-theme-info',
    outline: 'badge-theme-outline'
  };
  
  // Theme size classes
  const sizeClasses = {
    xs: 'badge-theme-xs',
    sm: 'badge-theme-sm',
    md: 'badge-theme-md',
    lg: 'badge-theme-lg'
  };
  
  // Rounded corner classes
  const roundedClasses = {
    md: 'badge-theme-rounded-md',
    lg: 'badge-theme-rounded-lg',
    full: 'badge-theme-rounded-full'
  };
  
  // Dot size classes
  const dotSizeClasses = {
    xs: 'badge-dot badge-dot-xs',
    sm: 'badge-dot badge-dot-sm',
    md: 'badge-dot badge-dot-md',
    lg: 'badge-dot badge-dot-lg'
  };
  
  // Remove button size classes
  const removeBtnSizeClasses = {
    xs: 'badge-remove-btn badge-remove-btn-xs',
    sm: 'badge-remove-btn badge-remove-btn-sm',
    md: 'badge-remove-btn badge-remove-btn-md',
    lg: 'badge-remove-btn badge-remove-btn-lg'
  };
  
  // eslint-disable-next-line security/detect-object-injection
  const selectedVariantClasses = variantClasses[variant] || variantClasses.default;
  // eslint-disable-next-line security/detect-object-injection
  const selectedSizeClasses = sizeClasses[size] || sizeClasses.sm;
  // eslint-disable-next-line security/detect-object-injection
  const selectedRoundedClasses = roundedClasses[rounded] || roundedClasses.full;
  // eslint-disable-next-line security/detect-object-injection
  const selectedDotSizeClasses = dotSizeClasses[size] || dotSizeClasses.sm;
  // eslint-disable-next-line security/detect-object-injection
  const selectedRemoveBtnClasses = removeBtnSizeClasses[size] || removeBtnSizeClasses.sm;
  
  return (
    <span 
      className={[
        baseClasses,
        selectedVariantClasses,
        selectedSizeClasses,
        selectedRoundedClasses,
        className
      ].filter(Boolean).join(' ')}
    >
      {/* Pulsing dot indicator */}
      {dot && (
        <span className="relative flex">
          {pulse && (
            <span className={`
              ${selectedDotSizeClasses}
              badge-dot-pulse absolute inline-flex h-full w-full opacity-75
              ${variant === 'success' ? 'bg-theme-success' :
                variant === 'warning' ? 'bg-theme-warning' :
                variant === 'danger' ? 'bg-theme-error' :
                variant === 'info' ? 'bg-theme-info' :
                'bg-theme-interactive-primary'}
            `} />
          )}
          <span className={`
            ${selectedDotSizeClasses}
            relative inline-flex
            ${variant === 'success' ? 'bg-theme-success' :
              variant === 'warning' ? 'bg-theme-warning' :
              variant === 'danger' ? 'bg-theme-error' :
              variant === 'info' ? 'bg-theme-info' :
              'bg-theme-interactive-primary'}
          `} />
        </span>
      )}
      
      {/* Icon */}
      {icon && (
        <span className="flex items-center">
          {icon}
        </span>
      )}
      
      {/* Badge content */}
      <span>
        {children}
      </span>
      
      {/* Remove button */}
      {removable && onRemove && (
        <button
          onClick={onRemove}
          className={selectedRemoveBtnClasses}
          aria-label="Remove"
        >
          <svg 
            className={`
              ${size === 'xs' || size === 'sm' ? 'w-2 h-2' : 
                size === 'md' ? 'w-2.5 h-2.5' :
                'w-3 h-3'}
            `}
            fill="currentColor" 
            viewBox="0 0 20 20"
          >
            <path 
              fillRule="evenodd" 
              d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" 
              clipRule="evenodd" 
            />
          </svg>
        </button>
      )}
    </span>
  );
};

export default Badge;