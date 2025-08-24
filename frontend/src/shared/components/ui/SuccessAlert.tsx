import React from 'react';
import { CheckCircle, X } from 'lucide-react';

interface SuccessAlertProps {
  message: string;
  onClose?: () => void;
}

const SuccessAlert: React.FC<SuccessAlertProps> = ({ message, onClose }) => {
  return (
    <div className="bg-theme-success bg-opacity-10 border border-theme-success rounded-lg p-4">
      <div className="flex items-start gap-3">
        <CheckCircle className="w-5 h-5 text-theme-success flex-shrink-0 mt-0.5" />
        <div className="flex-1">
          <p className="text-sm text-theme-success">{message}</p>
        </div>
        {onClose && (
          <button
            onClick={onClose}
            className="text-theme-success hover:text-theme-success-hover transition-colors duration-200 flex-shrink-0"
          >
            <X className="w-4 h-4" />
          </button>
        )}
      </div>
    </div>
  );
};

export default SuccessAlert;