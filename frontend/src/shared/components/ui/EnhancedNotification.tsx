import React, { useState } from 'react';
import {
  CheckCircle,
  XCircle,
  AlertTriangle,
  Info,
  X,
  ChevronDown,
  ChevronUp,
  Copy,
  Check
} from 'lucide-react';

interface NotificationProps {
  id: string;
  type: 'success' | 'error' | 'warning' | 'info';
  message: string;
  details?: Record<string, any>;
  onRemove: (id: string) => void;
}

export const EnhancedNotification: React.FC<NotificationProps> = ({
  id,
  type,
  message,
  details,
  onRemove
}) => {
  const [isExpanded, setIsExpanded] = useState(false);
  const [copied, setCopied] = useState(false);

  const hasDetails = details && Object.keys(details).length > 0;

  const getIcon = () => {
    switch (type) {
      case 'success':
        return <CheckCircle className="h-5 w-5 toast-icon" />;
      case 'error':
        return <XCircle className="h-5 w-5 toast-icon" />;
      case 'warning':
        return <AlertTriangle className="h-5 w-5 toast-icon" />;
      case 'info':
        return <Info className="h-5 w-5 toast-icon" />;
    }
  };

  const getToastClass = () => {
    switch (type) {
      case 'success':
        return 'toast-theme-success';
      case 'error':
        return 'toast-theme-error';
      case 'warning':
        return 'toast-theme-warning';
      case 'info':
        return 'toast-theme-info';
    }
  };

  const copyToClipboard = async () => {
    try {
      let copyText = message;

      if (hasDetails) {
        copyText += '\n\nDetails:\n';
        Object.entries(details!).forEach(([key, value]) => {
          copyText += `${key}: ${typeof value === 'object' ? JSON.stringify(value, null, 2) : value}\n`;
        });
      }

      await navigator.clipboard.writeText(copyText);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (error) {
      console.error('Failed to copy notification:', error);
    }
  };

  const formatDetailValue = (value: unknown): string => {
    if (typeof value === 'object') {
      return JSON.stringify(value, null, 2);
    }
    return String(value);
  };

  return (
    <div
      className={`
        ${getToastClass()}
        rounded-lg shadow-lg transition-all duration-200
        min-w-[320px] max-w-[600px] animate-fade-in
      `}
    >
      {/* Main notification content */}
      <div className="p-4">
        <div className="flex items-start justify-between">
          <div className="flex items-start space-x-3 flex-1">
            {getIcon()}
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium break-words">
                {message}
              </p>
            </div>
          </div>

          {/* Action buttons */}
          <div className="flex items-center space-x-1 ml-3">
            {/* Copy button */}
            <button
              onClick={copyToClipboard}
              className="p-1.5 rounded-full transition-colors duration-150 hover:bg-black/10 toast-icon"
              title="Copy notification"
              aria-label={copied ? 'Notification copied' : 'Copy notification'}
            >
              {copied ? (
                <Check className="h-4 w-4" />
              ) : (
                <Copy className="h-4 w-4" />
              )}
            </button>

            {/* Expand button (only if details exist) */}
            {hasDetails && (
              <button
                onClick={() => setIsExpanded(!isExpanded)}
                className="p-1.5 rounded-full transition-colors duration-150 hover:bg-black/10 toast-icon"
                title={isExpanded ? 'Collapse details' : 'Expand details'}
                aria-label={isExpanded ? 'Collapse notification details' : 'Expand notification details'}
                aria-expanded={isExpanded}
              >
                {isExpanded ? (
                  <ChevronUp className="h-4 w-4" />
                ) : (
                  <ChevronDown className="h-4 w-4" />
                )}
              </button>
            )}

            {/* Close button */}
            <button
              onClick={() => onRemove(id)}
              className="p-1.5 rounded-full transition-colors duration-150 hover:bg-black/10 toast-icon"
              title="Dismiss"
              aria-label="Dismiss notification"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>

        {/* Expanded details */}
        {hasDetails && isExpanded && (
          <div className="mt-3 pt-3 border-t border-current/20">
            <div className="space-y-2">
              {Object.entries(details!).map(([key, value]) => (
                <div key={key} className="text-xs">
                  <span className="font-medium">
                    {key.charAt(0).toUpperCase() + key.slice(1).replace(/([A-Z])/g, ' $1')}:
                  </span>
                  <div className="mt-1 opacity-80 font-mono whitespace-pre-wrap break-all">
                    {formatDetailValue(value)}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};