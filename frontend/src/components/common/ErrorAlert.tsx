import React from 'react';
import { AlertTriangle, X } from 'lucide-react';

interface ErrorAlertProps {
  message: string;
  onClose?: () => void;
}

const ErrorAlert: React.FC<ErrorAlertProps> = ({ message, onClose }) => {
  return (
    <div className="bg-theme-error bg-opacity-10 border border-theme-error rounded-lg p-4">
      <div className="flex items-start gap-3">
        <AlertTriangle className="w-5 h-5 text-theme-error flex-shrink-0 mt-0.5" />
        <div className="flex-1">
          <p className="text-sm text-theme-error">{message}</p>
        </div>
        {onClose && (
          <button
            onClick={onClose}
            className="text-theme-error hover:text-theme-error-hover transition-colors duration-200 flex-shrink-0"
          >
            <X className="w-4 h-4" />
          </button>
        )}
      </div>
    </div>
  );
};

export default ErrorAlert;