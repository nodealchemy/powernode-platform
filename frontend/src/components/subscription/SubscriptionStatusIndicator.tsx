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
  const { checkSubscriptionStatus, getDaysUntilExpiry, isTrialEnding, isExpiringSoon } = useSubscriptionLifecycle();
  
  const status = checkSubscriptionStatus(subscription);
  const daysUntilExpiry = getDaysUntilExpiry(subscription);

  const getStatusConfig = () => {
    switch (status) {
      case 'active':
        return {
          color: 'bg-green-100 text-green-800',
          icon: '✓',
          message: 'Active',
          description: showDetails ? `Next billing: ${new Date(subscription.currentPeriodEnd).toLocaleDateString()}` : undefined
        };
      case 'trial_ending':
        return {
          color: 'bg-yellow-100 text-yellow-800',
          icon: '⏰',
          message: 'Trial Ending',
          description: showDetails ? `Trial ends in ${daysUntilExpiry} day${daysUntilExpiry !== 1 ? 's' : ''}` : undefined
        };
      case 'expiring':
        return {
          color: 'bg-orange-100 text-orange-800',
          icon: '⚠️',
          message: 'Expiring Soon',
          description: showDetails ? `Expires in ${daysUntilExpiry} day${daysUntilExpiry !== 1 ? 's' : ''}` : undefined
        };
      case 'expired':
        return {
          color: 'bg-red-100 text-red-800',
          icon: '❌',
          message: 'Expired',
          description: showDetails ? 'Subscription has expired' : undefined
        };
      default:
        return {
          color: 'bg-gray-100 text-gray-800',
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
    <div className={`p-3 rounded-lg border ${config.color.includes('green') ? 'border-green-200' : 
                      config.color.includes('yellow') ? 'border-yellow-200' : 
                      config.color.includes('orange') ? 'border-orange-200' : 
                      config.color.includes('red') ? 'border-red-200' : 'border-gray-200'}`}>
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