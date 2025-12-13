import React, { forwardRef } from 'react';

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'danger' | 'success' | 'warning' | 'ghost' | 'outline';
  size?: 'xs' | 'sm' | 'md' | 'lg' | 'xl';
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
    elevation: _elevation = true,
    iconOnly = false,
    pulse = false,
    className = '',
    children,
    disabled,
    ...props
  }, ref) => {
    // _elevation prop reserved for future elevation styles
    void _elevation;
    // Base theme classes
    const baseClasses = 'btn-theme';
    
    // Theme variant classes - override for iconOnly
    const variantClasses = {
      primary: iconOnly ? 'text-theme-interactive-primary hover:bg-theme-surface-hover' : 'btn-theme-primary',
      secondary: iconOnly ? 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover' : 'btn-theme-secondary',
      outline: iconOnly ? 'text-theme-interactive-primary hover:bg-theme-surface-hover' : 'btn-theme-outline',
      ghost: iconOnly ? 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover' : 'btn-theme-ghost',
      danger: iconOnly ? 'text-theme-error hover:bg-theme-error-background' : 'btn-theme-danger',
      success: iconOnly ? 'text-theme-success hover:bg-theme-success-background' : 'btn-theme-success',
      warning: iconOnly ? 'text-theme-warning hover:bg-theme-warning-background' : 'btn-theme-warning'
    };
    
    // Theme size classes
    const sizeClasses = {
      xs: iconOnly ? 'btn-theme-icon-xs' : 'btn-theme-xs',
      sm: iconOnly ? 'btn-theme-icon-sm' : 'btn-theme-sm',
      md: iconOnly ? 'btn-theme-icon-md' : 'btn-theme-md',
      lg: iconOnly ? 'btn-theme-icon-lg' : 'btn-theme-lg',
      xl: iconOnly ? 'btn-theme-icon-xl' : 'btn-theme-xl'
    };
    
    // Additional classes for features not covered by theme
    const additionalClasses = [
      fullWidth ? 'btn-theme-full' : '',
      loading ? 'btn-theme-loading' : '',
      pulse && !disabled ? 'animate-pulse' : '',
      // IconOnly buttons get standardized styling with no border/background
      iconOnly ? 'bg-transparent border-none shadow-none' : '',
      // Keep rounded classes as theme doesn't specify button-specific radius
      rounded === 'md' ? 'rounded-md' :
      rounded === 'lg' ? 'rounded-lg' :
      rounded === 'xl' ? 'rounded-xl' :
      rounded === 'full' ? 'rounded-full' : 'rounded-lg'
    ].filter(Boolean);
    
    // eslint-disable-next-line security/detect-object-injection
    const selectedVariantClasses = variantClasses[variant] || variantClasses.primary;
    // eslint-disable-next-line security/detect-object-injection
    const selectedSizeClasses = sizeClasses[size] || sizeClasses.md;
    
    return (
      <button
        ref={ref}
        className={[
          baseClasses,
          selectedVariantClasses,
          selectedSizeClasses,
          ...additionalClasses,
          className
        ].filter(Boolean).join(' ')}
        disabled={disabled || loading}
        {...props}
      >
        {/* Loading spinner - keep existing implementation as theme doesn't provide spinner */}
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
        
        {/* Button content - simplified as theme handles most styling */}
        {children}
      </button>
    );
  }
);


export default Button;