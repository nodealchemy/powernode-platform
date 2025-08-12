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
  // Enhanced base classes with modern styling
  const baseClasses = `
    inline-flex items-center justify-center
    font-semibold tracking-wide
    transition-all duration-200 ease-out
    transform hover:scale-105
    ${removable ? 'pr-1' : ''}
  `;
  
  // Modern variant styles with gradients and better contrast
  const variantClasses = {
    default: `
      bg-gradient-to-r from-theme-surface to-theme-surface-hover
      text-theme-secondary 
      border border-theme
      shadow-sm
    `,
    primary: `
      bg-gradient-to-r from-theme-interactive-primary to-theme-interactive-primary-hover
      text-white
      shadow-md shadow-theme-interactive-primary/20
    `,
    secondary: `
      bg-gradient-to-r from-theme-surface-selected to-theme-surface-pressed
      text-theme-primary 
      border border-theme-focus
      shadow-sm
    `,
    success: `
      bg-gradient-to-r from-theme-success to-theme-success-hover
      text-white
      shadow-md shadow-theme-success/20
    `,
    warning: `
      bg-gradient-to-r from-theme-warning to-theme-warning-hover
      text-white
      shadow-md shadow-theme-warning/20
    `,
    danger: `
      bg-gradient-to-r from-theme-error to-theme-error-hover
      text-white
      shadow-md shadow-theme-error/20
    `,
    info: `
      bg-gradient-to-r from-theme-info to-theme-info-hover
      text-white
      shadow-md shadow-theme-info/20
    `,
    outline: `
      bg-transparent
      text-theme-primary
      border-2 border-theme-interactive-primary
      hover:bg-theme-interactive-primary hover:text-white
    `
  };
  
  // Enhanced size classes
  const sizeClasses = {
    xs: 'px-2 py-0.5 text-xs gap-1',
    sm: 'px-2.5 py-1 text-xs gap-1.5',
    md: 'px-3 py-1.5 text-sm gap-2',
    lg: 'px-4 py-2 text-base gap-2.5'
  };
  
  // Rounded corner variants
  const roundedClasses = {
    md: 'rounded-md',
    lg: 'rounded-lg',
    full: 'rounded-full'
  };
  
  // Dot size classes
  const dotSizeClasses = {
    xs: 'w-1.5 h-1.5',
    sm: 'w-2 h-2',
    md: 'w-2.5 h-2.5',
    lg: 'w-3 h-3'
  };
  
  // eslint-disable-next-line security/detect-object-injection
  const selectedVariantClasses = variantClasses[variant] || variantClasses.default;
  // eslint-disable-next-line security/detect-object-injection
  const selectedSizeClasses = sizeClasses[size] || sizeClasses.sm;
  // eslint-disable-next-line security/detect-object-injection
  const selectedRoundedClasses = roundedClasses[rounded] || roundedClasses.full;
  // eslint-disable-next-line security/detect-object-injection
  const selectedDotSizeClasses = dotSizeClasses[size] || dotSizeClasses.sm;
  
  return (
    <span 
      className={`
        ${baseClasses} 
        ${selectedVariantClasses} 
        ${selectedSizeClasses} 
        ${selectedRoundedClasses}
        ${className}
      `.replace(/\s+/g, ' ').trim()}
    >
      {/* Pulsing dot indicator */}
      {dot && (
        <span className="relative flex">
          <span className={`
            ${selectedDotSizeClasses}
            ${pulse ? 'animate-ping absolute inline-flex h-full w-full rounded-full opacity-75' : ''}
            ${variant === 'success' ? 'bg-theme-success opacity-75' :
              variant === 'warning' ? 'bg-theme-warning opacity-75' :
              variant === 'danger' ? 'bg-theme-error opacity-75' :
              variant === 'info' ? 'bg-theme-info opacity-75' :
              'bg-theme-interactive-primary'}
          `} />
          <span className={`
            ${selectedDotSizeClasses}
            relative inline-flex rounded-full
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
      <span className="relative">
        {children}
      </span>
      
      {/* Remove button */}
      {removable && onRemove && (
        <button
          onClick={onRemove}
          className={`
            ml-1 -mr-0.5 inline-flex items-center justify-center
            rounded-full hover:bg-theme-surface-hover
            transition-colors duration-200
            focus:outline-none focus:ring-2 focus:ring-offset-1
            ${size === 'xs' ? 'w-3 h-3' : 
              size === 'sm' ? 'w-3.5 h-3.5' :
              size === 'md' ? 'w-4 h-4' :
              'w-5 h-5'}
          `}
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
      
      {/* Shine effect overlay for non-outline variants */}
      {variant !== 'outline' && variant !== 'default' && (
        <span className="absolute inset-0 rounded-inherit overflow-hidden pointer-events-none">
          <span className="absolute inset-0 bg-gradient-to-t from-transparent via-white/10 to-white/20 opacity-0 hover:opacity-100 transition-opacity duration-300" />
        </span>
      )}
    </span>
  );
};

export default Badge;