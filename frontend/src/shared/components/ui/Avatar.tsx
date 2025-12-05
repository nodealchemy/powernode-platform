import React from 'react';

export interface AvatarProps {
  className?: string;
  size?: 'xs' | 'sm' | 'md' | 'lg' | 'xl';
  src?: string;
  alt?: string;
  fallback?: string;
  initials?: string;
  children?: React.ReactNode;
}

export const Avatar: React.FC<AvatarProps> = ({
  className = '',
  size = 'md',
  src,
  alt = 'Avatar',
  fallback,
  initials,
  children
}) => {
  const sizeClasses = {
    xs: 'h-6 w-6 text-xs',
    sm: 'h-8 w-8 text-sm',
    md: 'h-10 w-10 text-base',
    lg: 'h-12 w-12 text-lg',
    xl: 'h-16 w-16 text-xl'
  };

  const baseClasses = `
    rounded-full 
    bg-gradient-to-br from-theme-interactive-primary to-theme-interactive-secondary 
    flex items-center justify-center 
    text-white font-semibold 
    overflow-hidden
    ${sizeClasses[size]}
    ${className}
  `.trim();

  // If children are provided, render them directly
  if (children) {
    return (
      <div className={baseClasses}>
        {children}
      </div>
    );
  }

  // If src is provided, render image
  if (src) {
    return (
      <div className={baseClasses}>
        <img 
          src={src} 
          alt={alt} 
          className="w-full h-full object-cover"
          onError={(e) => {
            // Hide image on error and show fallback
            (e.target as HTMLImageElement).style.display = 'none';
          }}
        />
        {/* Fallback content */}
        <span className="absolute inset-0 flex items-center justify-center">
          {initials || fallback || alt.charAt(0).toUpperCase()}
        </span>
      </div>
    );
  }

  // Default: render initials or fallback
  return (
    <div className={baseClasses}>
      <span>
        {initials || fallback || 'U'}
      </span>
    </div>
  );
};

export default Avatar;