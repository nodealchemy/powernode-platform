import React from 'react';
import { AlertTriangle, X } from 'lucide-react';

interface ErrorAlertProps {
  message: string;
  onClose?: () => void;
}

const ErrorAlert: React.FC<ErrorAlertProps> = ({ message, onClose }) => {
  return (
    <div className="bg-theme-error-bg border border-theme-error-border rounded-lg p-4">
      <div className="flex items-start gap-3">
        <AlertTriangle className="w-5 h-5 text-theme-error-fg flex-shrink-0 mt-0.5" />
        <div className="flex-1">
          <p className="text-sm text-theme-error-fg">{message}</p>
        </div>
        {onClose && (
          <button
            onClick={onClose}
            className="text-theme-error-fg hover:text-theme-error-hover transition-colors duration-200 flex-shrink-0"
            aria-label="Dismiss"
          >
            <X className="w-4 h-4" />
          </button>
        )}
      </div>
    </div>
  );
};

export default ErrorAlert;