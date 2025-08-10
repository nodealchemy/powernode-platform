import React, { useState } from 'react';
import { Subscription, Plan } from '../../services/subscriptionService';

interface SubscriptionModalProps {
  isOpen: boolean;
  onClose: () => void;
  subscription: Subscription | null;
  availablePlans: Plan[];
  onUpgrade?: (planId: string) => void;
  onCancel?: (subscriptionId: string) => void;
  loading?: boolean;
}

export const SubscriptionModal: React.FC<SubscriptionModalProps> = ({
  isOpen,
  onClose,
  subscription,
  availablePlans,
  onUpgrade,
  onCancel,
  loading = false,
}) => {
  const [selectedPlanId, setSelectedPlanId] = useState<string>('');
  const [showCancelConfirm, setShowCancelConfirm] = useState(false);

  if (!isOpen || !subscription) return null;

  const formatDate = (dateString: string | null | undefined) => {
    if (!dateString) return 'No expiration';
    
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return 'No expiration';
    
    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  };

  const formatPrice = (price: {cents: number; currency_iso: string} | number | null | undefined, currency?: string) => {
    let priceCents: number;
    
    if (price == null) {
      return 'Free';
    }
    
    if (typeof price === 'object' && 'cents' in price) {
      priceCents = price.cents;
      currency = currency || price.currency_iso;
    } else if (typeof price === 'number') {
      priceCents = price;
    } else {
      return 'Free';
    }
    
    if (priceCents === 0 || isNaN(priceCents)) {
      return 'Free';
    }
    
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency || 'USD',
    }).format(priceCents / 100);
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active':
        return 'bg-green-100 text-green-800';
      case 'trialing':
        return 'bg-blue-100 text-blue-800';
      case 'cancelled':
        return 'bg-red-100 text-red-800';
      case 'past_due':
        return 'bg-yellow-100 text-yellow-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  const availableUpgrades = availablePlans.filter(plan => 
    plan.id !== subscription.plan.id && 
    plan.price > subscription.plan.price &&
    plan.status === 'active'
  );

  const handleUpgrade = () => {
    if (selectedPlanId && onUpgrade) {
      onUpgrade(selectedPlanId);
    }
  };

  const handleCancel = () => {
    if (onCancel) {
      onCancel(subscription.id);
      setShowCancelConfirm(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 overflow-y-auto h-full w-full z-50" onClick={onClose}>
      <div className="relative top-20 mx-auto p-5 border-theme w-full max-w-2xl shadow-lg rounded-md card-theme" onClick={(e) => e.stopPropagation()}>
        <div className="flex justify-between items-center mb-4">
          <h3 className="text-lg font-medium text-theme-primary">Manage Subscription</h3>
          <button
            onClick={onClose}
            className="text-theme-tertiary hover:text-theme-secondary"
          >
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div className="space-y-6">
          {/* Current Subscription Info */}
          <div className="bg-theme-background-secondary p-4 rounded-lg">
            <h4 className="text-sm font-medium text-theme-primary mb-3">Current Subscription</h4>
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span className="text-theme-secondary">Plan:</span>
                <p className="font-medium">{subscription.plan.name}</p>
              </div>
              <div>
                <span className="text-theme-secondary">Price:</span>
                <p className="font-medium">{formatPrice(subscription.plan.price)}/{subscription.plan.billing_cycle || subscription.plan.interval}</p>
              </div>
              <div>
                <span className="text-theme-secondary">Status:</span>
                <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getStatusColor(subscription.status)}`}>
                  {subscription.status}
                </span>
              </div>
              <div>
                <span className="text-theme-secondary">
                  {subscription.currentPeriodEnd ? 'Next Billing:' : 'Billing:'}
                </span>
                <p className="font-medium">{formatDate(subscription.currentPeriodEnd)}</p>
              </div>
              {subscription.trialEndsAt && (
                <div className="col-span-2">
                  <span className="text-theme-secondary">Trial Ends:</span>
                  <p className="font-medium">{formatDate(subscription.trialEndsAt)}</p>
                </div>
              )}
            </div>
          </div>

          {/* Upgrade Options */}
          {availableUpgrades.length > 0 && subscription.status === 'active' && (
            <div>
              <h4 className="text-sm font-medium text-theme-primary mb-3">Upgrade Plan</h4>
              <div className="space-y-2">
                {availableUpgrades.map((plan) => (
                  <label key={plan.id} className="flex items-center p-3 border-theme rounded-lg hover:bg-theme-background-secondary cursor-pointer">
                    <input
                      type="radio"
                      name="upgrade-plan"
                      value={plan.id}
                      checked={selectedPlanId === plan.id}
                      onChange={(e) => setSelectedPlanId(e.target.value)}
                      className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300"
                    />
                    <div className="ml-3 flex-1">
                      <div className="flex justify-between items-center">
                        <p className="text-sm font-medium text-theme-primary">{plan.name}</p>
                        <p className="text-sm text-theme-secondary">{formatPrice(plan.price)}/{plan.billing_cycle || plan.interval}</p>
                      </div>
                    </div>
                  </label>
                ))}
              </div>
              {selectedPlanId && (
                <button
                  onClick={handleUpgrade}
                  disabled={loading}
                  className="btn-theme btn-theme-primary mt-3 w-full py-2 px-4 disabled:opacity-50"
                >
                  {loading ? 'Processing...' : 'Upgrade Plan'}
                </button>
              )}
            </div>
          )}

          {/* Cancel Subscription */}
          {subscription.status === 'active' && !showCancelConfirm && (
            <div className="border-t pt-4">
              <button
                onClick={() => setShowCancelConfirm(true)}
                className="text-red-600 hover:text-red-700 text-sm font-medium transition-colors"
              >
                Cancel Subscription
              </button>
            </div>
          )}

          {/* Cancel Confirmation */}
          {showCancelConfirm && (
            <div className="border border-red-300 bg-red-50 p-4 rounded-lg">
              <h5 className="text-sm font-medium text-red-800 mb-2">Cancel Subscription?</h5>
              <p className="text-sm text-red-700 mb-3">
                {subscription.currentPeriodEnd 
                  ? `Your subscription will remain active until ${formatDate(subscription.currentPeriodEnd)}, after which you'll lose access to premium features.`
                  : 'Cancelling will immediately end your subscription and you\'ll lose access to premium features.'
                }
              </p>
              <div className="flex space-x-2">
                <button
                  onClick={handleCancel}
                  disabled={loading}
                  className="bg-red-600 hover:bg-red-700 text-white px-3 py-1 rounded-md text-sm disabled:opacity-50 transition-colors"
                >
                  {loading ? 'Canceling...' : 'Yes, Cancel'}
                </button>
                <button
                  onClick={() => setShowCancelConfirm(false)}
                  className="btn-theme btn-theme-secondary px-3 py-1 rounded-md text-sm"
                >
                  Keep Subscription
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};