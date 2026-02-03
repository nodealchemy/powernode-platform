
import { SubscriptionStatusIndicator } from './SubscriptionStatusIndicator';
import { Subscription } from '@/shared/types';
import { CreditCard, Calendar, Clock, TrendingUp } from 'lucide-react';
import { formatSubscriptionPrice, type BillingCycle } from '@/shared/utils/formatters';

interface CurrentPlanSummaryProps {
  subscription: Subscription | null;
  loading?: boolean;
  onManage?: () => void;
  className?: string;
}

export const CurrentPlanSummary: React.FC<CurrentPlanSummaryProps> = ({
  subscription,
  loading = false,
  onManage,
  className = ''
}) => {
  const formatDisplayDate = (dateString: string | null | undefined) => {
    if (!dateString) return 'Never expires';

    const date = new Date(dateString);
    if (isNaN(date.getTime())) return 'Never expires';

    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  };

  const getDaysRemaining = (subscription: Subscription): number => {
    if (!subscription.current_period_end) return 0;

    const endDate = new Date(subscription.current_period_end);
    const now = new Date();
    const diffTime = endDate.getTime() - now.getTime();
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));

    return Math.max(0, diffDays);
  };

  if (loading) {
    return null;
  }

  if (!subscription) {
    return (
      <div className={`text-sm text-theme-secondary ${className}`}>
        No active subscription.
      </div>
    );
  }

  const daysRemaining = getDaysRemaining(subscription);
  const isTrialing = subscription.status === 'trialing';

  return (
    <div className={`card-theme shadow p-6 ${className}`}>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-theme-primary">Current Plan</h3>
        <SubscriptionStatusIndicator 
          subscription={subscription} 
          showDetails={false}
        />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Plan Information */}
        <div className="space-y-4">
          <div>
            <div className="flex items-center space-x-3 mb-2">
              <TrendingUp className="h-5 w-5 text-theme-link" />
              <h4 className="font-semibold text-theme-primary">{subscription.plan.name}</h4>
            </div>
            <p className="text-2xl font-bold text-theme-primary">
              {formatSubscriptionPrice(subscription.plan.price_cents, subscription.plan.billing_cycle as BillingCycle, subscription.plan.currency)}
            </p>
            <p className="text-sm text-theme-secondary">
              {subscription.plan.billing_cycle} billing
            </p>
          </div>

          {/* Plan Features */}
          {subscription.plan.features && typeof subscription.plan.features === 'object' && (
            <div>
              <p className="text-sm font-medium text-theme-primary mb-2">Key Features:</p>
              <div className="space-y-1">
                {Object.entries(subscription.plan.features).slice(0, 3).map(([key, value]) => (
                  <div key={key} className="flex items-center text-sm text-theme-primary">
                    <div className="w-2 h-2 bg-theme-success-solid rounded-full mr-2"></div>
                    {typeof value === 'boolean' && value ? key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()) : `${key}: ${value}`}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Billing Information */}
        <div className="space-y-4">
          <div className="flex items-start space-x-3">
            <Calendar className="h-5 w-5 text-theme-secondary mt-1" />
            <div>
              <p className="font-medium text-theme-primary">
                {isTrialing ? 'Trial Ends' : 'Next Billing'}
              </p>
              <p className="text-sm text-theme-secondary">
                {formatDisplayDate(isTrialing ? subscription.trial_end : subscription.current_period_end)}
              </p>
            </div>
          </div>

          <div className="flex items-start space-x-3">
            <Clock className="h-5 w-5 text-theme-secondary mt-1" />
            <div>
              <p className="font-medium text-theme-primary">Days Remaining</p>
              <p className="text-sm text-theme-secondary">
                {daysRemaining} day{daysRemaining !== 1 ? 's' : ''} 
                {isTrialing ? ' in trial' : ' until renewal'}
              </p>
            </div>
          </div>

          {/* Trial Warning */}
          {isTrialing && daysRemaining <= 7 && (
            <div className="p-3 rounded-lg bg-theme-warning border border-theme-warning">
              <p className="text-sm font-medium text-theme-warning">
                Trial ending soon!
              </p>
              <p className="text-xs text-theme-warning mt-1">
                Choose a plan to continue using premium features.
              </p>
            </div>
          )}
        </div>
      </div>

      {/* Action Button */}
      {onManage && (
        <div className="mt-6 pt-4 border-t border-theme">
          <button
            onClick={onManage}
            className="btn-theme btn-theme-primary w-full md:w-auto"
          >
            <CreditCard className="h-4 w-4 mr-2" />
            Manage Subscription
          </button>
        </div>
      )}
    </div>
  );
};