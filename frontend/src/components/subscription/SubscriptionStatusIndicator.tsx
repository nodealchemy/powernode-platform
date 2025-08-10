import React from 'react';
import { useSubscriptionLifecycle } from '../../hooks/useSubscriptionLifecycle';
import { Subscription } from '../../services/subscriptionService';

interface SubscriptionStatusIndicatorProps {
  subscription: Subscription;
  showDetails?: boolean;
}

export const SubscriptionStatusIndicator: React.FC<SubscriptionStatusIndicatorProps> = ({
  subscription,
  showDetails = false,
}) => {
  const { checkSubscriptionStatus, getDaysUntilExpiry } = useSubscriptionLifecycle();
  // TODO: Use isTrialEnding and isExpiringSoon for enhanced status indicators
  
  const status = checkSubscriptionStatus(subscription);
  const daysUntilExpiry = getDaysUntilExpiry(subscription);

  const formatDate = (dateString: string | null | undefined) => {
    if (!dateString) return 'No expiration';
    
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return 'No expiration';
    
    return date.toLocaleDateString();
  };

  const getStatusConfig = () => {
    switch (status) {
      case 'active':
        return {
          color: 'bg-theme-success text-theme-success',
          icon: '✓',
          message: 'Active',
          description: showDetails ? (
            subscription.currentPeriodEnd ? `Next billing: ${formatDate(subscription.currentPeriodEnd)}` : 'Never expires'
          ) : undefined
        };
      case 'trial_ending':
        return {
          color: 'bg-theme-warning text-theme-warning',
          icon: '⏰',
          message: 'Trial Ending',
          description: showDetails ? `Trial ends in ${daysUntilExpiry} day${daysUntilExpiry !== 1 ? 's' : ''}` : undefined
        };
      case 'expiring':
        return {
          color: 'bg-theme-warning text-theme-warning',
          icon: '⚠️',
          message: 'Expiring Soon',
          description: showDetails ? `Expires in ${daysUntilExpiry} day${daysUntilExpiry !== 1 ? 's' : ''}` : undefined
        };
      case 'expired':
        return {
          color: 'bg-theme-error text-theme-error',
          icon: '❌',
          message: 'Expired',
          description: showDetails ? 'Subscription has expired' : undefined
        };
      default:
        return {
          color: 'bg-theme-background-secondary text-theme-secondary',
          icon: '●',
          message: subscription.status.charAt(0).toUpperCase() + subscription.status.slice(1),
          description: undefined
        };
    }
  };

  const config = getStatusConfig();

  if (!showDetails) {
    return (
      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${config.color}`}>
        <span className="mr-1">{config.icon}</span>
        {config.message}
      </span>
    );
  }

  return (
    <div className={`p-3 rounded-lg border ${config.color.includes('success') ? 'border-theme-success' : 
                      config.color.includes('warning') ? 'border-theme-warning' : 
                      config.color.includes('error') ? 'border-theme-error' : 'border-theme'}`}>
      <div className="flex items-center">
        <span className="text-lg mr-2">{config.icon}</span>
        <div>
          <p className="font-medium text-sm">{config.message}</p>
          {config.description && (
            <p className="text-xs opacity-75">{config.description}</p>
          )}
        </div>
      </div>
      
      {/* Additional warnings for critical states */}
      {(status === 'trial_ending' || status === 'expiring') && (
        <div className="mt-2 text-xs">
          <p className="font-medium">Action Required:</p>
          <p>Please update your payment method or subscription will be suspended.</p>
        </div>
      )}
    </div>
  );
};