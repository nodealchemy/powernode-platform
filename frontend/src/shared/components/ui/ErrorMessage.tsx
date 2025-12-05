import React from 'react';
import { AlertCircle } from 'lucide-react';

interface ErrorMessageProps {
  title?: string;
  message: string;
  className?: string;
}

export const ErrorMessage: React.FC<ErrorMessageProps> = ({
  title = 'Error',
  message,
  className = ''
}) => {
  return (
    <div className={`flex items-start gap-3 p-4 bg-theme-error bg-opacity-10 border border-theme-error border-opacity-20 rounded-lg ${className}`}>
      <AlertCircle className="h-5 w-5 text-theme-error mt-0.5 flex-shrink-0" />
      <div>
        <p className="text-sm font-medium text-theme-error">{title}</p>
        <p className="text-sm text-theme-secondary mt-1">{message}</p>
      </div>
    </div>
  );
};