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
    size: _size = 'md',
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
    // _size prop reserved for future size-based content scaling
    void _size;
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
    
     
    const selectedVariantClasses = variantClasses[variant] || variantClasses.default;
     
    const selectedPaddingClasses = paddingClasses[padding] || paddingClasses.md;
     
    const selectedRoundedClasses = roundedClasses[rounded] || roundedClasses.xl;
     
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

// Metric Card Component for dashboard statistics
export interface MetricCardProps {
  title: string;
  value: string | number;
  icon?: string | React.ReactNode;
  change?: number | null;
  changeLabel?: string;
  description?: string;
  onClick?: () => void;
  className?: string;
}

export const MetricCard: React.FC<MetricCardProps> = ({
  title,
  value,
  icon,
  change,
  changeLabel,
  description,
  onClick,
  className = ''
}) => {
  const getChangeColor = (change: number | null | undefined) => {
    if (typeof change !== 'number' || change === null || change === undefined) {
      return 'text-theme-secondary';
    }
    if (change > 0) return 'text-theme-success';
    if (change < 0) return 'text-theme-error';
    return 'text-theme-secondary';
  };

  const getChangeIcon = (change: number | null | undefined) => {
    if (typeof change !== 'number' || change === null || change === undefined) {
      return '→';
    }
    if (change > 0) return '↗️';
    if (change < 0) return '↘️';
    return '→';
  };

  const formatChange = (change: number | null | undefined) => {
    if (change === null || change === undefined || typeof change !== 'number') {
      return '0.0%';
    }
    const sign = change > 0 ? '+' : '';
    return `${sign}${change.toFixed(1)}%`;
  };

  return (
    <Card 
      variant="elevated" 
      padding="lg" 
      hoverable={!!onClick} 
      clickable={!!onClick}
      onClick={onClick}
      className={className}
    >
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-medium text-theme-secondary">{title}</h3>
          {icon && (
            <div className="w-8 h-8 flex items-center justify-center">
              {typeof icon === 'string' ? (
                <span className="text-lg">{icon}</span>
              ) : icon}
            </div>
          )}
        </div>
        
        <div className="space-y-1">
          <div className="text-2xl font-bold text-theme-primary">
            {typeof value === 'number' ? value.toLocaleString() : value}
          </div>
          
          {(change !== undefined || description) && (
            <div className="flex items-center justify-between">
              {change !== undefined && change !== null && (
                <div className={`flex items-center gap-1 text-sm ${getChangeColor(change)}`}>
                  <span>{getChangeIcon(change)}</span>
                  <span>{formatChange(change)}</span>
                  {changeLabel && <span className="text-theme-tertiary">{changeLabel}</span>}
                </div>
              )}
              {description && (change === undefined || change === null) && (
                <div className="text-xs text-theme-tertiary">{description}</div>
              )}
            </div>
          )}
        </div>
      </div>
    </Card>
  );
};

// Action Card Component for quick actions and navigation
export interface ActionCardProps {
  title: string;
  description: string;
  icon?: string | React.ReactNode;
  badge?: string;
  status?: 'normal' | 'warning' | 'error' | 'success';
  onClick?: () => void;
  href?: string;
  className?: string;
}

export const ActionCard: React.FC<ActionCardProps> = ({
  title,
  description,
  icon,
  badge,
  status = 'normal',
  onClick,
  href,
  className = ''
}) => {
  const getStatusClasses = (status: string) => {
    switch (status) {
      case 'warning':
        return 'border-theme-warning-border bg-theme-warning-background';
      case 'error':
        return 'border-theme-error-border bg-theme-error-background';
      case 'success':
        return 'border-theme-success-border bg-theme-success-background';
      default:
        return '';
    }
  };

  const cardContent = (
    <Card 
      hoverable 
      clickable={!!onClick}
      onClick={onClick}
      className={`${getStatusClasses(status)} relative overflow-hidden ${className}`}
      padding="lg"
    >
      {badge && (
        <div className="absolute top-3 right-3 z-10">
          <span className="px-2 py-1 bg-theme-interactive-primary text-white text-xs font-medium rounded-full">
            {badge}
          </span>
        </div>
      )}
      
      <div className="flex items-start gap-4">
        {icon && (
          <div className="w-12 h-12 bg-theme-background rounded-lg flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform">
            {typeof icon === 'string' ? (
              <span className="text-xl">{icon}</span>
            ) : icon}
          </div>
        )}
        
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary mb-1 group-hover:text-theme-link transition-colors">
            {title}
          </h3>
          <p className="text-sm text-theme-secondary line-clamp-2">
            {description}
          </p>
        </div>
        
        <div className="text-theme-tertiary group-hover:text-theme-primary transition-colors">
          →
        </div>
      </div>
    </Card>
  );

  if (href && !onClick) {
    return (
      <a href={href} className="block">
        {cardContent}
      </a>
    );
  }

  return cardContent;
};

// Standard Card Sub-components for consistency with shadcn/ui pattern
export interface CardTitleProps {
  children: React.ReactNode;
  className?: string;
}

export const CardTitle: React.FC<CardTitleProps> = ({
  children,
  className = ''
}) => {
  return (
    <h3 className={`text-lg font-semibold text-theme-primary ${className}`}>
      {children}
    </h3>
  );
};

export interface CardDescriptionProps {
  children: React.ReactNode;
  className?: string;
}

export const CardDescription: React.FC<CardDescriptionProps> = ({
  children,
  className = ''
}) => {
  return (
    <p className={`text-sm text-theme-secondary ${className}`}>
      {children}
    </p>
  );
};

export interface CardContentProps {
  children: React.ReactNode;
  className?: string;
}

export const CardContent: React.FC<CardContentProps> = ({
  children,
  className = ''
}) => {
  return (
    <div className={`text-theme-secondary ${className}`}>
      {children}
    </div>
  );
};

export default Card;