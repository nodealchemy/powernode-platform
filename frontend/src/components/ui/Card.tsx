import React, { forwardRef } from 'react';

export interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  variant?: 'default' | 'elevated' | 'outlined' | 'glass' | 'gradient';
  size?: 'sm' | 'md' | 'lg';
  padding?: 'none' | 'sm' | 'md' | 'lg' | 'xl';
  hoverable?: boolean;
  clickable?: boolean;
  selected?: boolean;
  rounded?: 'none' | 'sm' | 'md' | 'lg' | 'xl' | '2xl';
  shadow?: 'none' | 'sm' | 'md' | 'lg' | 'xl' | '2xl';
  gradient?: {
    from: string;
    to: string;
    direction?: string;
  };
  borderGlow?: boolean;
  className?: string;
  children: React.ReactNode;
}

export const Card = forwardRef<HTMLDivElement, CardProps>(
  ({ 
    variant = 'default',
    size = 'md',
    padding = 'md',
    hoverable = false,
    clickable = false,
    selected = false,
    rounded = 'xl',
    shadow = 'md',
    gradient,
    borderGlow = false,
    className = '',
    children,
    onClick,
    ...props
  }, ref) => {
    // Enhanced base classes with modern styling
    const baseClasses = `
      relative overflow-hidden
      transition-all duration-300 ease-out
      ${clickable ? 'cursor-pointer' : ''}
    `;
    
    // Modern variant styles
    const variantClasses = {
      default: `
        bg-theme-surface
        border border-theme-surface
        ${hoverable ? 'hover:border-theme hover:shadow-lg hover:-translate-y-1' : ''}
        ${selected ? 'ring-2 ring-theme-interactive-primary ring-offset-2 ring-offset-theme-background' : ''}
      `,
      elevated: `
        bg-theme-surface
        ${hoverable ? 'hover:shadow-2xl hover:-translate-y-2' : ''}
        ${selected ? 'ring-2 ring-theme-interactive-primary ring-offset-2 ring-offset-theme-background' : ''}
      `,
      outlined: `
        bg-transparent
        border-2 border-theme
        ${hoverable ? 'hover:border-theme-interactive-primary hover:bg-theme-surface hover:shadow-md hover:-translate-y-1' : ''}
        ${selected ? 'border-theme-interactive-primary bg-theme-surface-selected' : ''}
      `,
      glass: `
        bg-theme-surface/10 backdrop-blur-md
        border border-theme-surface/20
        ${hoverable ? 'hover:bg-theme-surface/20 hover:shadow-xl hover:-translate-y-1' : ''}
        ${selected ? 'ring-2 ring-theme-interactive-primary/50' : ''}
      `,
      gradient: `
        ${gradient ? `bg-gradient-to-${gradient.direction || 'br'}` : 'bg-gradient-to-br from-theme-interactive-primary to-theme-interactive-primary-hover'}
        text-white
        ${hoverable ? 'hover:shadow-2xl hover:scale-[1.02] hover:-translate-y-1' : ''}
        ${selected ? 'ring-2 ring-white ring-offset-2 ring-offset-theme-background' : ''}
      `
    };
    
    // Size-based padding classes
    const paddingClasses = {
      none: '',
      sm: 'p-3',
      md: 'p-4 sm:p-5',
      lg: 'p-5 sm:p-6',
      xl: 'p-6 sm:p-8'
    };
    
    // Rounded corner variants
    const roundedClasses = {
      none: 'rounded-none',
      sm: 'rounded-sm',
      md: 'rounded-md',
      lg: 'rounded-lg',
      xl: 'rounded-xl',
      '2xl': 'rounded-2xl'
    };
    
    // Shadow variants
    const shadowClasses = {
      none: '',
      sm: 'shadow-sm',
      md: 'shadow-md',
      lg: 'shadow-lg',
      xl: 'shadow-xl',
      '2xl': 'shadow-2xl'
    };
    
    // Border glow effect
    const borderGlowClasses = borderGlow ? `
      before:absolute before:inset-0 
      before:p-[2px] before:rounded-inherit
      before:bg-gradient-to-r before:from-theme-interactive-primary before:via-theme-interactive-primary-hover before:to-theme-interactive-secondary
      before:-z-10 before:animate-gradient-shift
      before:opacity-0 hover:before:opacity-100
      before:transition-opacity before:duration-500
    ` : '';
    
    // Dynamic gradient styles
    const gradientStyles = gradient && variant === 'gradient' ? {
      background: `linear-gradient(to ${gradient.direction || 'bottom right'}, ${gradient.from}, ${gradient.to})`
    } : {};
    
    // eslint-disable-next-line security/detect-object-injection
    const selectedVariantClasses = variantClasses[variant] || variantClasses.default;
    // eslint-disable-next-line security/detect-object-injection
    const selectedPaddingClasses = paddingClasses[padding] || paddingClasses.md;
    // eslint-disable-next-line security/detect-object-injection
    const selectedRoundedClasses = roundedClasses[rounded] || roundedClasses.xl;
    // eslint-disable-next-line security/detect-object-injection
    const selectedShadowClasses = shadowClasses[shadow] || shadowClasses.md;
    
    return (
      <div
        ref={ref}
        className={`
          ${baseClasses}
          ${selectedVariantClasses}
          ${selectedPaddingClasses}
          ${selectedRoundedClasses}
          ${selectedShadowClasses}
          ${borderGlowClasses}
          ${className}
        `.replace(/\s+/g, ' ').trim()}
        onClick={onClick}
        style={gradientStyles}
        {...props}
      >
        {/* Top accent line for default and elevated variants */}
        {(variant === 'default' || variant === 'elevated') && (
          <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-theme-interactive-primary via-theme-interactive-primary-hover to-theme-interactive-primary opacity-0 hover:opacity-100 transition-opacity duration-300" />
        )}
        
        {/* Content */}
        <div className="relative z-10">
          {children}
        </div>
        
        {/* Hover overlay for interactive cards */}
        {(hoverable || clickable) && variant !== 'glass' && (
          <div className="absolute inset-0 bg-gradient-to-t from-transparent to-theme-interactive-primary/5 opacity-0 hover:opacity-100 transition-opacity duration-300 pointer-events-none" />
        )}
        
        {/* Selection indicator */}
        {selected && (
          <div className="absolute top-3 right-3 z-20">
            <div className="w-6 h-6 bg-theme-interactive-primary rounded-full flex items-center justify-center animate-scale-in">
              <svg className="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
              </svg>
            </div>
          </div>
        )}
      </div>
    );
  }
);

Card.displayName = 'Card';

// Card Header Component
export interface CardHeaderProps {
  title: string;
  subtitle?: string;
  icon?: React.ReactNode;
  action?: React.ReactNode;
  className?: string;
}

export const CardHeader: React.FC<CardHeaderProps> = ({
  title,
  subtitle,
  icon,
  action,
  className = ''
}) => {
  return (
    <div className={`flex items-start justify-between mb-4 ${className}`}>
      <div className="flex items-start gap-3">
        {icon && (
          <div className="flex-shrink-0 w-10 h-10 bg-theme-interactive-primary/10 rounded-lg flex items-center justify-center text-theme-interactive-primary">
            {icon}
          </div>
        )}
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">{title}</h3>
          {subtitle && (
            <p className="text-sm text-theme-secondary mt-0.5">{subtitle}</p>
          )}
        </div>
      </div>
      {action && (
        <div className="flex-shrink-0">
          {action}
        </div>
      )}
    </div>
  );
};

// Card Body Component
export interface CardBodyProps {
  children: React.ReactNode;
  className?: string;
}

export const CardBody: React.FC<CardBodyProps> = ({
  children,
  className = ''
}) => {
  return (
    <div className={`text-theme-secondary ${className}`}>
      {children}
    </div>
  );
};

// Card Footer Component
export interface CardFooterProps {
  children: React.ReactNode;
  className?: string;
  divider?: boolean;
}

export const CardFooter: React.FC<CardFooterProps> = ({
  children,
  className = '',
  divider = true
}) => {
  return (
    <div className={`
      ${divider ? 'border-t border-theme pt-4 mt-4' : 'mt-4'}
      ${className}
    `}>
      {children}
    </div>
  );
};

export default Card;