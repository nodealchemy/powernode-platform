import React from 'react';
import { Card, Badge } from '@/shared/components/ui';
import type { ResellerCommission } from '../types';

interface CommissionTrackerProps {
  commissions: ResellerCommission[];
  lifetimeEarnings: number;
  pendingPayout: number;
}

const STATUS_CONFIG: Record<string, { label: string; variant: 'success' | 'warning' | 'error' | 'default' }> = {
  pending: { label: 'Pending', variant: 'warning' },
  available: { label: 'Available', variant: 'success' },
  paid: { label: 'Paid', variant: 'default' },
  cancelled: { label: 'Cancelled', variant: 'error' },
  clawed_back: { label: 'Clawed Back', variant: 'error' },
};

const TYPE_LABELS: Record<string, string> = {
  signup_bonus: 'Signup Bonus',
  recurring: 'Recurring',
  one_time: 'One-Time',
  upgrade_bonus: 'Upgrade Bonus',
};

export const CommissionTracker: React.FC<CommissionTrackerProps> = ({
  commissions,
  lifetimeEarnings,
  pendingPayout,
}) => {
  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
    }).format(amount);
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Commission Tracker</h3>
          <p className="text-sm text-theme-tertiary">Your earnings and commissions</p>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4 mb-6">
        <div className="p-4 rounded-lg bg-theme-surface">
          <p className="text-sm text-theme-tertiary mb-1">Lifetime Earnings</p>
          <p className="text-2xl font-bold text-theme-primary">{formatCurrency(lifetimeEarnings)}</p>
        </div>
        <div className="p-4 rounded-lg bg-theme-surface">
          <p className="text-sm text-theme-tertiary mb-1">Available for Payout</p>
          <p className="text-2xl font-bold text-green-600">{formatCurrency(pendingPayout)}</p>
        </div>
      </div>

      <div className="border-t border-theme pt-4">
        <h4 className="text-sm font-medium text-theme-secondary mb-4">Recent Commissions</h4>

        {commissions.length === 0 ? (
          <p className="text-center text-theme-tertiary py-8">
            No commissions yet. Start referring customers to earn!
          </p>
        ) : (
          <div className="space-y-3">
            {commissions.map((commission) => {
              const statusConfig = STATUS_CONFIG[commission.status] || STATUS_CONFIG.pending;

              return (
                <div
                  key={commission.id}
                  className="flex items-center justify-between p-3 rounded-lg bg-theme-surface hover:bg-theme-hover transition-colors"
                >
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <span className="font-medium text-theme-primary">
                        {formatCurrency(commission.commission_amount)}
                      </span>
                      <Badge variant={statusConfig.variant} size="sm">
                        {statusConfig.label}
                      </Badge>
                    </div>
                    <div className="flex items-center gap-2 text-sm text-theme-tertiary">
                      <span>{TYPE_LABELS[commission.commission_type] || commission.commission_type}</span>
                      <span>•</span>
                      <span>{formatDate(commission.earned_at)}</span>
                    </div>
                  </div>

                  <div className="text-right">
                    <p className="text-sm text-theme-tertiary">
                      {commission.commission_percentage}% of {formatCurrency(commission.gross_amount)}
                    </p>
                    {commission.status === 'pending' && commission.days_until_available !== undefined && (
                      <p className="text-xs text-amber-600">
                        Available in {commission.days_until_available} days
                      </p>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </Card>
  );
};
