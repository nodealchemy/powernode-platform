
import { SubscriptionStatusIndicator } from './SubscriptionStatusIndicator';
import { Subscription } from '@/shared/types';
import { CreditCard, Calendar, Clock, TrendingUp } from 'lucide-react';

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
  const formatDate = (dateString: string | null | undefined) => {
    if (!dateString) return 'Never expires';
    
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return 'Never expires';
    
    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  };

  const formatPrice = (price: {cents: number; currency_iso: string} | number | null | undefined, interval?: string) => {
    let priceCents: number;
    
    if (price == null) {
      return 'Free';
    }
    
    if (typeof price === 'object' && 'cents' in price) {
      priceCents = price.cents;
    } else if (typeof price === 'number') {
      priceCents = price;
    } else {
      return 'Free';
    }
    
    if (priceCents === 0 || isNaN(priceCents)) {
      return 'Free';
    }
    
    const formattedPrice = (priceCents / 100).toFixed(2);
    return interval ? `$${formattedPrice}/${interval}` : `$${formattedPrice}`;
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
    return (
      <div className={`card-theme shadow p-6 ${className}`}>
        <div className="animate-pulse">
          <div className="flex items-center justify-between mb-4">
            <div className="h-6 bg-theme-secondary rounded w-32"></div>
            <div className="h-8 bg-theme-secondary rounded w-24"></div>
          </div>
          <div className="space-y-3">
            <div className="h-4 bg-theme-secondary rounded w-48"></div>
            <div className="h-4 bg-theme-secondary rounded w-36"></div>
            <div className="h-4 bg-theme-secondary rounded w-42"></div>
          </div>
        </div>
      </div>
    );
  }

  if (!subscription) {
    return (
      <div className={`card-theme shadow p-6 ${className}`}>
        <div className="text-center">
          <div className="mx-auto w-16 h-16 rounded-full flex items-center justify-center mb-4 bg-theme-secondary">
            <CreditCard className="h-8 w-8 text-theme-primary" />
          </div>
          <h3 className="text-lg font-medium text-theme-primary mb-2">No Active Subscription</h3>
          <p className="text-sm text-theme-secondary mb-4">
            Choose a plan below to get started with premium features.
          </p>
          {onManage && (
            <button
              onClick={onManage}
              className="btn-theme btn-theme-primary"
            >
              Browse Plans
            </button>
          )}
        </div>
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
              {formatPrice(subscription.plan.price_cents, subscription.plan.billing_cycle)}
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
                  <div key={key} className="flex items-center text-sm text-theme-secondary">
                    <div className="w-2 h-2 bg-theme-success rounded-full mr-2"></div>
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
                {formatDate(isTrialing ? subscription.trial_end : subscription.current_period_end)}
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