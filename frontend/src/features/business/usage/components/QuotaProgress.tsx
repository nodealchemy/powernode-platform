import React from 'react';
import { Card } from '@/shared/components/ui';
import type { UsageQuota } from '../types';

interface QuotaProgressProps {
  quotas: UsageQuota[];
}

export const QuotaProgress: React.FC<QuotaProgressProps> = ({ quotas }) => {
  if (quotas.length === 0) {
    return (
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Usage Quotas</h3>
        <p className="text-center text-theme-tertiary py-8">
          No usage quotas configured.
        </p>
      </Card>
    );
  }

  const getProgressColor = (quota: UsageQuota) => {
    if (quota.exceeded) return 'bg-theme-error';
    if (quota.at_critical) return 'bg-theme-error';
    if (quota.at_warning) return 'bg-theme-warning';
    return 'bg-theme-interactive-primary';
  };

  const getStatusBadge = (quota: UsageQuota) => {
    if (quota.exceeded) {
      return (
        <span className="px-2 py-1 text-xs font-medium rounded bg-theme-error-background text-theme-error">
          Exceeded
        </span>
      );
    }
    if (quota.at_critical) {
      return (
        <span className="px-2 py-1 text-xs font-medium rounded bg-theme-error-background text-theme-error">
          Critical
        </span>
      );
    }
    if (quota.at_warning) {
      return (
        <span className="px-2 py-1 text-xs font-medium rounded bg-theme-warning-background text-theme-warning">
          Warning
        </span>
      );
    }
    return (
      <span className="px-2 py-1 text-xs font-medium rounded bg-theme-success-background text-theme-success">
        OK
      </span>
    );
  };

  const formatNumber = (num: number) => {
    return new Intl.NumberFormat('en-US').format(num);
  };

  return (
    <Card className="p-6">
      <h3 className="text-lg font-semibold text-theme-primary mb-4">Usage Quotas</h3>

      <div className="space-y-6">
        {quotas.map((quota) => (
          <div key={quota.id} className="space-y-2">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="font-medium text-theme-primary">{quota.meter_name}</span>
                {getStatusBadge(quota)}
              </div>
              <span className="text-sm text-theme-secondary">
                {formatNumber(quota.current_usage)} / {formatNumber(quota.soft_limit || quota.hard_limit || 0)} {quota.unit_name}
              </span>
            </div>

            <div className="w-full bg-theme-tertiary rounded-full h-3">
              <div
                className={`h-3 rounded-full transition-all ${getProgressColor(quota)}`}
                style={{ width: `${Math.min(quota.usage_percent, 100)}%` }}
              />
            </div>

            <div className="flex items-center justify-between text-sm">
              <span className="text-theme-tertiary">
                {quota.usage_percent.toFixed(1)}% used
              </span>
              <span className="text-theme-tertiary">
                {quota.remaining !== undefined && quota.remaining !== null
                  ? `${formatNumber(quota.remaining)} remaining`
                  : 'Unlimited'}
              </span>
            </div>

            {quota.allow_overage && quota.overage_rate && quota.overage_amount && quota.overage_amount > 0 && (
              <div className="text-sm text-theme-warning">
                Overage charges: ${quota.overage_amount.toFixed(2)} ({formatNumber(quota.current_usage - (quota.soft_limit || quota.hard_limit || 0))} {quota.unit_name} @ ${quota.overage_rate}/{quota.unit_name})
              </div>
            )}
          </div>
        ))}
      </div>
    </Card>
  );
};
