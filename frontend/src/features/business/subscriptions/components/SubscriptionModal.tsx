import React, { useState } from 'react';
import { Subscription, SubscriptionPlan as Plan } from '@/shared/types';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { CreditCard, TrendingUp, AlertCircle } from 'lucide-react';

interface SubscriptionModalProps {
  isOpen: boolean;
  onClose: () => void;
  subscription: Subscription | null;
  availablePlans: Plan[];
  onUpgrade?: (plan_id: string) => void;
  onCancel?: (subscription_id: string) => void;
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

  if (!subscription) return null;

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

  const formatPrice = (priceCents: number | null | undefined, currency?: string) => {
    if (priceCents == null || priceCents === 0 || isNaN(priceCents)) {
      return 'Free';
    }

    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency || 'USD',
    }).format(priceCents / 100);
  };

  const getStatusVariant = (status: string): 'success' | 'info' | 'danger' | 'warning' | 'secondary' => {
    switch (status) {
      case 'active':
        return 'success';
      case 'trialing':
        return 'info';
      case 'cancelled':
        return 'danger';
      case 'past_due':
        return 'warning';
      default:
        return 'secondary';
    }
  };

  const availableUpgrades = availablePlans.filter(plan =>
    plan.id !== subscription.plan.id &&
    plan.price_cents > subscription.plan.price_cents &&
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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Manage Subscription"
      subtitle="View and manage your current subscription plan"
      icon={<CreditCard />}
      maxWidth="2xl"
      closeOnBackdrop={!loading}
      closeOnEscape={!loading}
    >
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
                <p className="font-medium">{formatPrice(subscription.plan.price_cents, subscription.plan.currency)}/{subscription.plan.billing_cycle}</p>
              </div>
              <div>
                <span className="text-theme-secondary">Status:</span>
                <div className="mt-1">
                  <Badge variant={getStatusVariant(subscription.status)} size="sm">
                    {subscription.status}
                  </Badge>
                </div>
              </div>
              <div>
                <span className="text-theme-secondary">
                  {subscription.current_period_end ? 'Next Billing:' : 'Billing:'}
                </span>
                <p className="font-medium">{formatDate(subscription.current_period_end)}</p>
              </div>
              {subscription.trial_end && (
                <div className="col-span-2">
                  <span className="text-theme-secondary">Trial Ends:</span>
                  <p className="font-medium">{formatDate(subscription.trial_end)}</p>
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
                      className="h-4 w-4 text-theme-interactive-primary focus:ring-theme-interactive-primary border-theme"
                    />
                    <div className="ml-3 flex-1">
                      <div className="flex justify-between items-center">
                        <p className="text-sm font-medium text-theme-primary">{plan.name}</p>
                        <p className="text-sm text-theme-secondary">{formatPrice(plan.price_cents, plan.currency)}/{plan.billing_cycle}</p>
                      </div>
                    </div>
                  </label>
                ))}
              </div>
              {selectedPlanId && (
                <Button
                  onClick={handleUpgrade}
                  variant="primary"
                  fullWidth
                  loading={loading}
                  className="mt-3"
                >
                  {!loading && <TrendingUp className="w-4 h-4 mr-2" />}
                  {loading ? 'Processing...' : 'Upgrade Plan'}
                </Button>
              )}
            </div>
          )}

          {/* Cancel Subscription */}
          {subscription.status === 'active' && !showCancelConfirm && (
            <div className="border-t pt-4">
              <Button
                onClick={() => setShowCancelConfirm(true)}
                variant="ghost"
                size="sm"
                className="text-theme-error hover:text-theme-error-hover"
              >
                <AlertCircle className="w-4 h-4 mr-2" />
                Cancel Subscription
              </Button>
            </div>
          )}

          {/* Cancel Confirmation */}
          {showCancelConfirm && (
            <div className="border border-theme-error-border bg-theme-error-background p-4 rounded-lg">
              <h5 className="text-sm font-medium text-theme-error mb-2">Cancel Subscription?</h5>
              <p className="text-sm text-theme-error mb-3">
                {subscription.current_period_end
                  ? `Your subscription will remain active until ${formatDate(subscription.current_period_end)}, after which you'll lose access to premium features.`
                  : 'Cancelling will immediately end your subscription and you\'ll lose access to premium features.'
                }
              </p>
              <div className="flex space-x-2">
                <Button
                  onClick={handleCancel}
                  variant="danger"
                  size="sm"
                  loading={loading}
                >
                  {loading ? 'Canceling...' : 'Yes, Cancel'}
                </Button>
                <Button
                  onClick={() => setShowCancelConfirm(false)}
                  variant="secondary"
                  size="sm"
                >
                  Keep Subscription
                </Button>
              </div>
            </div>
          )}
        </div>
    </Modal>
  );
};