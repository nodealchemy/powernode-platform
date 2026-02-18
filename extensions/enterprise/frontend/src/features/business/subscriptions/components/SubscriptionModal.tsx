import React, { useState } from 'react';
import { Subscription, SubscriptionPlan as Plan } from '@/shared/types';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { CreditCard, TrendingUp, TrendingDown, AlertCircle, ArrowRight } from 'lucide-react';
import {
  formatCurrency,
  formatSubscriptionPrice,
  normalizePriceCents,
  type BillingCycle,
} from '@/shared/utils/formatters';

interface SubscriptionModalProps {
  isOpen: boolean;
  onClose: () => void;
  subscription: Subscription | null;
  availablePlans: Plan[];
  onUpgrade?: (plan_id: string) => void;
  onDowngrade?: (plan_id: string) => void;
  onCancel?: (subscription_id: string) => void;
  loading?: boolean;
}

export const SubscriptionModal: React.FC<SubscriptionModalProps> = ({
  isOpen,
  onClose,
  subscription,
  availablePlans,
  onUpgrade,
  onDowngrade,
  onCancel,
  loading = false,
}) => {
  const [selectedPlanId, setSelectedPlanId] = useState<string>('');
  const [showCancelConfirm, setShowCancelConfirm] = useState(false);
  const [activeTab, setActiveTab] = useState<'upgrade' | 'downgrade'>('upgrade');

  // Reset state when modal closes
  const handleClose = () => {
    setSelectedPlanId('');
    setShowCancelConfirm(false);
    setActiveTab('upgrade');
    onClose();
  };

  if (!subscription) return null;

  const formatDisplayDate = (dateString: string | null | undefined) => {
    if (!dateString) return 'No expiration';

    const date = new Date(dateString);
    if (isNaN(date.getTime())) return 'No expiration';

    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  };

  const getStatusVariant = (status: string): 'success' | 'info' | 'danger' | 'warning' | 'secondary' => {
    switch (status) {
      case 'active':
        return 'success';
      case 'trialing':
        return 'info';
      case 'cancelled':
      case 'canceled':
        return 'danger';
      case 'past_due':
        return 'warning';
      case 'paused':
        return 'secondary';
      default:
        return 'secondary';
    }
  };

  const currentPlanPrice = normalizePriceCents(subscription.plan.price_cents);

  const availableUpgrades = availablePlans.filter(plan =>
    plan.id !== subscription.plan.id &&
    normalizePriceCents(plan.price_cents) > currentPlanPrice &&
    plan.status === 'active'
  );

  const availableDowngrades = availablePlans.filter(plan =>
    plan.id !== subscription.plan.id &&
    normalizePriceCents(plan.price_cents) < currentPlanPrice &&
    plan.status === 'active'
  );

  const handlePlanChange = () => {
    if (!selectedPlanId) return;

    const selectedPlan = availablePlans.find(p => p.id === selectedPlanId);
    if (!selectedPlan) return;

    const selectedPrice = normalizePriceCents(selectedPlan.price_cents);
    const isUpgrade = selectedPrice > currentPlanPrice;

    if (isUpgrade && onUpgrade) {
      onUpgrade(selectedPlanId);
    } else if (!isUpgrade && onDowngrade) {
      onDowngrade(selectedPlanId);
    } else if (onUpgrade) {
      // Fallback to onUpgrade for both if onDowngrade not provided
      onUpgrade(selectedPlanId);
    }
  };

  const handleCancel = () => {
    if (onCancel) {
      onCancel(subscription.id);
      setShowCancelConfirm(false);
    }
  };

  const getPriceDifference = (plan: Plan) => {
    const planPrice = normalizePriceCents(plan.price_cents);
    const diff = planPrice - currentPlanPrice;
    const formatted = formatCurrency(Math.abs(diff), plan.currency || 'USD');
    return {
      amount: diff,
      formatted,
      isIncrease: diff > 0,
    };
  };

  const canChangePlan = subscription.status === 'active' || subscription.status === 'trialing';
  const hasUpgrades = availableUpgrades.length > 0;
  const hasDowngrades = availableDowngrades.length > 0;

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
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
              <p className="font-medium">
                {formatSubscriptionPrice(
                  subscription.plan.price_cents,
                  subscription.plan.billing_cycle as BillingCycle,
                  subscription.plan.currency
                )}
              </p>
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
              <p className="font-medium">{formatDisplayDate(subscription.current_period_end)}</p>
            </div>
            {subscription.trial_end && (
              <div className="col-span-2">
                <span className="text-theme-secondary">Trial Ends:</span>
                <p className="font-medium">{formatDisplayDate(subscription.trial_end)}</p>
              </div>
            )}
          </div>
        </div>

        {/* Plan Change Options */}
        {canChangePlan && (hasUpgrades || hasDowngrades) && (
          <div>
            {/* Tab Navigation */}
            {hasUpgrades && hasDowngrades && (
              <div className="flex border-b border-theme mb-4">
                <button
                  onClick={() => {
                    setActiveTab('upgrade');
                    setSelectedPlanId('');
                  }}
                  className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
                    activeTab === 'upgrade'
                      ? 'border-theme-primary text-theme-primary'
                      : 'border-transparent text-theme-secondary hover:text-theme-primary'
                  }`}
                >
                  <TrendingUp className="w-4 h-4 inline mr-1" />
                  Upgrade
                </button>
                <button
                  onClick={() => {
                    setActiveTab('downgrade');
                    setSelectedPlanId('');
                  }}
                  className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
                    activeTab === 'downgrade'
                      ? 'border-theme-primary text-theme-primary'
                      : 'border-transparent text-theme-secondary hover:text-theme-primary'
                  }`}
                >
                  <TrendingDown className="w-4 h-4 inline mr-1" />
                  Downgrade
                </button>
              </div>
            )}

            {/* Upgrade Options */}
            {(activeTab === 'upgrade' || !hasDowngrades) && hasUpgrades && (
              <div>
                <h4 className="text-sm font-medium text-theme-primary mb-3">
                  {hasDowngrades ? '' : 'Upgrade Plan'}
                </h4>
                <div className="space-y-2">
                  {availableUpgrades.map((plan) => {
                    const priceDiff = getPriceDifference(plan);
                    return (
                      <label
                        key={plan.id}
                        className={`flex items-center p-3 border rounded-lg cursor-pointer transition-colors ${
                          selectedPlanId === plan.id
                            ? 'border-theme-primary bg-theme-primary bg-opacity-5'
                            : 'border-theme hover:bg-theme-background-secondary'
                        }`}
                      >
                        <input
                          type="radio"
                          name="plan-change"
                          value={plan.id}
                          checked={selectedPlanId === plan.id}
                          onChange={(e) => setSelectedPlanId(e.target.value)}
                          className="h-4 w-4 text-theme-interactive-primary focus:ring-theme-interactive-primary border-theme"
                        />
                        <div className="ml-3 flex-1">
                          <div className="flex justify-between items-center">
                            <div>
                              <p className="text-sm font-medium text-theme-primary">{plan.name}</p>
                              <p className="text-xs text-theme-success">
                                +{priceDiff.formatted}/{plan.billing_cycle}
                              </p>
                            </div>
                            <p className="text-sm text-theme-secondary">
                              {formatSubscriptionPrice(plan.price_cents, plan.billing_cycle as BillingCycle, plan.currency)}
                            </p>
                          </div>
                        </div>
                      </label>
                    );
                  })}
                </div>
              </div>
            )}

            {/* Downgrade Options */}
            {activeTab === 'downgrade' && hasDowngrades && (
              <div>
                <div className="bg-theme-warning bg-opacity-10 border border-theme-warning rounded-lg p-3 mb-4">
                  <p className="text-sm text-theme-warning">
                    <AlertCircle className="w-4 h-4 inline mr-1" />
                    Downgrading may result in losing access to certain features. Your new plan will take effect at the end of your current billing period.
                  </p>
                </div>
                <div className="space-y-2">
                  {availableDowngrades.map((plan) => {
                    const priceDiff = getPriceDifference(plan);
                    return (
                      <label
                        key={plan.id}
                        className={`flex items-center p-3 border rounded-lg cursor-pointer transition-colors ${
                          selectedPlanId === plan.id
                            ? 'border-theme-primary bg-theme-primary bg-opacity-5'
                            : 'border-theme hover:bg-theme-background-secondary'
                        }`}
                      >
                        <input
                          type="radio"
                          name="plan-change"
                          value={plan.id}
                          checked={selectedPlanId === plan.id}
                          onChange={(e) => setSelectedPlanId(e.target.value)}
                          className="h-4 w-4 text-theme-interactive-primary focus:ring-theme-interactive-primary border-theme"
                        />
                        <div className="ml-3 flex-1">
                          <div className="flex justify-between items-center">
                            <div>
                              <p className="text-sm font-medium text-theme-primary">{plan.name}</p>
                              <p className="text-xs text-theme-secondary">
                                Save {priceDiff.formatted}/{plan.billing_cycle}
                              </p>
                            </div>
                            <p className="text-sm text-theme-secondary">
                              {formatSubscriptionPrice(plan.price_cents, plan.billing_cycle as BillingCycle, plan.currency)}
                            </p>
                          </div>
                        </div>
                      </label>
                    );
                  })}
                </div>
              </div>
            )}

            {/* Action Button */}
            {selectedPlanId && (
              <Button
                onClick={handlePlanChange}
                variant={activeTab === 'upgrade' ? 'primary' : 'secondary'}
                fullWidth
                loading={loading}
                className="mt-4"
              >
                {!loading && (activeTab === 'upgrade' ? (
                  <TrendingUp className="w-4 h-4 mr-2" />
                ) : (
                  <TrendingDown className="w-4 h-4 mr-2" />
                ))}
                {loading ? 'Processing...' : activeTab === 'upgrade' ? 'Upgrade Plan' : 'Downgrade Plan'}
                {!loading && <ArrowRight className="w-4 h-4 ml-2" />}
              </Button>
            )}
          </div>
        )}

        {/* No Plan Changes Available */}
        {canChangePlan && !hasUpgrades && !hasDowngrades && (
          <div className="text-center py-4 text-theme-secondary">
            <p className="text-sm">No other plans are currently available.</p>
          </div>
        )}

        {/* Cancel Subscription */}
        {(subscription.status === 'active' || subscription.status === 'trialing') && !showCancelConfirm && (
          <div className="border-t border-theme pt-4">
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
                ? `Your subscription will remain active until ${formatDisplayDate(subscription.current_period_end)}, after which you'll lose access to premium features.`
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