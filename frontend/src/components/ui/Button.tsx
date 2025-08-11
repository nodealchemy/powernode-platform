import React, { forwardRef } from 'react';

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'danger' | 'success' | 'warning' | 'ghost' | 'outline';
  size?: 'sm' | 'md' | 'lg' | 'xl';
  loading?: boolean;
  fullWidth?: boolean;
  rounded?: 'md' | 'lg' | 'xl' | 'full';
  elevation?: boolean;
  iconOnly?: boolean;
  pulse?: boolean;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ 
    variant = 'primary', 
    size = 'md', 
    loading = false,
    fullWidth = false,
    rounded = 'lg',
    elevation = true,
    iconOnly = false,
    pulse = false,
    className = '', 
    children, 
    disabled,
    ...props 
  }, ref) => {
    // Enhanced base classes with modern styling
    const baseClasses = `
      relative inline-flex items-center justify-center 
      font-semibold tracking-wide
      transition-all duration-300 ease-out
      transform-gpu
      focus:outline-none focus:ring-2 focus:ring-offset-2 
      focus:ring-offset-theme-background 
      disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none
      overflow-hidden
    `;
    
    // Modern variant styles with gradients and enhanced hover states
    const variantClasses = {
      primary: `
        bg-gradient-to-r from-theme-interactive-primary to-theme-interactive-primary-hover
        text-white 
        hover:shadow-lg hover:shadow-theme-interactive-primary/25 hover:-translate-y-0.5
        active:translate-y-0 active:shadow-md
        focus:ring-theme-interactive-primary
        ${elevation ? 'shadow-md shadow-theme-interactive-primary/20' : ''}
      `,
      secondary: `
        bg-theme-surface 
        border-2 border-theme 
        text-theme-primary 
        hover:bg-theme-surface-hover hover:border-theme-interactive-primary/30
        hover:-translate-y-0.5
        active:translate-y-0
        focus:ring-theme-focus
        ${elevation ? 'shadow-sm' : ''}
      `,
      outline: `
        bg-transparent
        border-2 border-theme-interactive-primary
        text-theme-interactive-primary
        hover:bg-theme-interactive-primary hover:text-white
        hover:shadow-lg hover:shadow-theme-interactive-primary/25
        hover:-translate-y-0.5
        active:translate-y-0
        focus:ring-theme-interactive-primary
      `,
      ghost: `
        bg-transparent
        text-theme-secondary
        hover:bg-theme-surface-hover hover:text-theme-primary
        hover:translate-x-1
        focus:ring-theme-focus
      `,
      danger: `
        bg-gradient-to-r from-red-600 to-red-700
        text-white 
        hover:from-red-700 hover:to-red-800
        hover:shadow-lg hover:shadow-red-600/25 hover:-translate-y-0.5
        active:translate-y-0 active:shadow-md
        focus:ring-red-500
        ${elevation ? 'shadow-md shadow-red-600/20' : ''}
      `,
      success: `
        bg-gradient-to-r from-green-600 to-green-700
        text-white 
        hover:from-green-700 hover:to-green-800
        hover:shadow-lg hover:shadow-green-600/25 hover:-translate-y-0.5
        active:translate-y-0 active:shadow-md
        focus:ring-green-500
        ${elevation ? 'shadow-md shadow-green-600/20' : ''}
      `,
      warning: `
        bg-gradient-to-r from-amber-500 to-amber-600
        text-white 
        hover:from-amber-600 hover:to-amber-700
        hover:shadow-lg hover:shadow-amber-600/25 hover:-translate-y-0.5
        active:translate-y-0 active:shadow-md
        focus:ring-amber-500
        ${elevation ? 'shadow-md shadow-amber-600/20' : ''}
      `
    };
    
    // Enhanced size classes with better proportions
    const sizeClasses = {
      sm: iconOnly ? 'p-2 text-sm' : 'px-3.5 py-2 text-sm gap-1.5',
      md: iconOnly ? 'p-2.5 text-base' : 'px-5 py-2.5 text-sm gap-2',
      lg: iconOnly ? 'p-3 text-lg' : 'px-6 py-3 text-base gap-2.5',
      xl: iconOnly ? 'p-4 text-xl' : 'px-8 py-4 text-lg gap-3'
    };
    
    // Rounded corner variants
    const roundedClasses = {
      md: 'rounded-md',
      lg: 'rounded-lg',
      xl: 'rounded-xl',
      full: 'rounded-full'
    };
    
    const widthClasses = fullWidth ? 'w-full' : '';
    const pulseClasses = pulse && !disabled ? 'animate-pulse' : '';
    
    // eslint-disable-next-line security/detect-object-injection
    const selectedVariantClasses = variantClasses[variant] || variantClasses.primary;
    // eslint-disable-next-line security/detect-object-injection
    const selectedSizeClasses = sizeClasses[size] || sizeClasses.md;
    // eslint-disable-next-line security/detect-object-injection
    const selectedRoundedClasses = roundedClasses[rounded] || roundedClasses.lg;
    
    return (
      <button
        ref={ref}
        className={`
          ${baseClasses} 
          ${selectedVariantClasses} 
          ${selectedSizeClasses} 
          ${selectedRoundedClasses}
          ${widthClasses} 
          ${pulseClasses}
          ${className}
        `.replace(/\s+/g, ' ').trim()}
        disabled={disabled || loading}
        {...props}
      >
        {/* Ripple effect overlay */}
        <span className="absolute inset-0 overflow-hidden rounded-inherit">
          <span className="absolute inset-0 rounded-inherit bg-current opacity-0 hover:opacity-10 transition-opacity duration-300" />
        </span>
        
        {/* Loading spinner with improved animation */}
        {loading && (
          <svg className="animate-spin -ml-1 mr-2 h-4 w-4 text-current" fill="none" viewBox="0 0 24 24">
            <circle
              className="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              strokeWidth="4"
            />
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
            />
          </svg>
        )}
        
        {/* Button content with relative positioning */}
        <span className="relative z-10">
          {children}
        </span>
        
        {/* Shine effect for primary buttons */}
        {variant === 'primary' && !disabled && (
          <span className="absolute inset-0 -top-[2px] h-[2px] bg-gradient-to-r from-transparent via-white/30 to-transparent opacity-0 hover:opacity-100 transition-opacity duration-500" />
        )}
      </button>
    );
  }
);

Button.displayName = 'Button';

export default Button;