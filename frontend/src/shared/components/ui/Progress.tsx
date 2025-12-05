import React from 'react';

export interface ProgressProps {
  value: number;
  max?: number;
  className?: string;
  size?: 'sm' | 'md' | 'lg';
  variant?: 'default' | 'success' | 'warning' | 'error';
  showLabel?: boolean;
}

export const Progress: React.FC<ProgressProps> = ({
  value,
  max = 100,
  className = '',
  size = 'md',
  variant = 'default',
  showLabel = false
}) => {
  const percentage = Math.min(Math.max((value / max) * 100, 0), 100);
  
  const sizeClasses = {
    sm: 'h-1',
    md: 'h-2',
    lg: 'h-3'
  };

  const variantClasses = {
    default: 'bg-theme-interactive-primary',
    success: 'bg-theme-success',
    warning: 'bg-theme-warning',
    error: 'bg-theme-error'
  };

  return (
    <div className={`w-full ${className}`}>
      <div className={`bg-theme-surface-secondary rounded-full overflow-hidden ${sizeClasses[size]}`}>
        <div
          className={`h-full transition-all duration-300 ease-out ${variantClasses[variant]}`}
          style={{ width: `${percentage}%` }}
        />
      </div>
      {showLabel && (
        <div className="flex justify-between text-xs text-theme-text-secondary mt-1">
          <span>{Math.round(percentage)}%</span>
          <span>{value} / {max}</span>
        </div>
      )}
    </div>
  );
};

export default Progress;