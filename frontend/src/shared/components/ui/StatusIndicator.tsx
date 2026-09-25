import React from 'react';
import { Badge } from '@/shared/components/ui/Badge';

export interface StatusIndicatorProps {
  status: 'active' | 'inactive' | 'pending' | 'error' | 'warning' | 'success' | 'loading';
  text?: string;
  showIcon?: boolean;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

const statusConfig = {
  active: {
    variant: 'success' as const,
    icon: '●',
    text: 'Active'
  },
  inactive: {
    variant: 'secondary' as const,
    icon: '○',
    text: 'Inactive'
  },
  pending: {
    variant: 'warning' as const,
    icon: '◐',
    text: 'Pending'
  },
  error: {
    variant: 'danger' as const,
    icon: '✕',
    text: 'Error'
  },
  warning: {
    variant: 'warning' as const,
    icon: '⚠',
    text: 'Warning'
  },
  success: {
    variant: 'success' as const,
    icon: '✓',
    text: 'Success'
  },
  loading: {
    variant: 'info' as const,
    icon: '◐',
    text: 'Loading'
  }
};

export const StatusIndicator: React.FC<StatusIndicatorProps> = ({
  status,
  text,
  showIcon = true,
  size = 'md',
  className = ''
}) => {
  const config = statusConfig[status];
  const displayText = text || config.text;

  return (
    <Badge 
      variant={config.variant} 
      size={size}
      className={className}
      icon={showIcon ? config.icon : undefined}
    >
      {displayText}
    </Badge>
  );
};

