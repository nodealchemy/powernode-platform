import React from 'react';
import { isDomainChanged, getDomainChangeMessage } from '@/shared/utils/domainUtils';

interface DomainChangeNoticeProps {
  onDismiss?: () => void;
}

/**
 * Shows a helpful notice when users access the app from a different domain
 * than where they originally authenticated
 */
export const DomainChangeNotice: React.FC<DomainChangeNoticeProps> = ({ onDismiss }) => {
  const [dismissed, setDismissed] = React.useState(false);
  
  // Don't show if not relevant or already dismissed
  if (!isDomainChanged() || dismissed) {
    return null;
  }
  
  const { title, message, previousDomain } = getDomainChangeMessage();
  
  const handleDismiss = () => {
    setDismissed(true);
    onDismiss?.();
  };
  
  return (
    <div className="bg-theme-warning/10 border border-theme-warning/20 rounded-lg p-4 mb-6">
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <h3 className="text-sm font-medium text-theme-warning-foreground mb-1">
            {title}
          </h3>
          <p className="text-sm text-theme-muted-foreground mb-2">
            {message}
          </p>
          {previousDomain && (
            <p className="text-xs text-theme-muted-foreground">
              Previous domain: {previousDomain}
            </p>
          )}
        </div>
        <button
          onClick={handleDismiss}
          className="ml-4 text-theme-muted-foreground hover:text-theme-foreground transition-colors"
          aria-label="Dismiss notice"
        >
          <svg className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
          </svg>
        </button>
      </div>
    </div>
  );
};