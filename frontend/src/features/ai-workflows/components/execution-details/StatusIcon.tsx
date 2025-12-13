import React from 'react';
import {
  CheckCircle,
  XCircle,
  Activity,
  AlertCircle,
  Clock
} from 'lucide-react';

interface StatusIconProps {
  status: string;
}

export const StatusIcon: React.FC<StatusIconProps> = ({ status }) => {
  switch (status) {
    case 'completed':
      return <CheckCircle className="h-4 w-4 text-theme-success" />;
    case 'failed':
      return <XCircle className="h-4 w-4 text-theme-error" />;
    case 'running':
      return <Activity className="h-4 w-4 text-theme-info animate-pulse" />;
    case 'pending':
      return <AlertCircle className="h-4 w-4 text-theme-warning" />;
    case 'cancelled':
      return <Clock className="h-4 w-4 text-theme-muted" />;
    default:
      return <AlertCircle className="h-4 w-4 text-theme-muted" />;
  }
};

// Helper function version for use in render props
export const renderStatusIcon = (status: string): React.ReactNode => {
  return <StatusIcon status={status} />;
};
