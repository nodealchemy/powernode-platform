import React from 'react';
import { LucideIcon } from 'lucide-react';

export interface EmptyStateProps {
  icon?: LucideIcon;
  title: string;
  description: string;
  action?: React.ReactElement;
  className?: string;
}

export const EmptyState: React.FC<EmptyStateProps> = ({
  icon: Icon,
  title,
  description,
  action,
  className = ''
}) => {
  return (
    <div className={`flex flex-col items-center justify-center text-center py-12 px-4 ${className}`}>
      {Icon && (
        <div className="h-16 w-16 bg-theme-surface-secondary rounded-full flex items-center justify-center mb-4">
          <Icon className="h-8 w-8 text-theme-text-tertiary" />
        </div>
      )}
      
      <h3 className="text-lg font-semibold text-theme-text-primary mb-2">
        {title}
      </h3>
      
      <p className="text-theme-text-secondary max-w-md mb-6">
        {description}
      </p>
      
      {action && (
        <div>
          {action}
        </div>
      )}
    </div>
  );
};

export default EmptyState;