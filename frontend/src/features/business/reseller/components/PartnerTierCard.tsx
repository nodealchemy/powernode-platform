import React from 'react';
import { Card } from '@/shared/components/ui';
import type { ResellerTier, TierBenefits } from '../types';

interface PartnerTierCardProps {
  currentTier: ResellerTier;
  tierBenefits?: TierBenefits;
  eligibleForUpgrade: boolean;
  nextTier?: ResellerTier;
  totalReferrals: number;
  totalRevenueGenerated: number;
}

const TIER_CONFIG: Record<ResellerTier, { label: string; color: string; bgColor: string }> = {
  bronze: { label: 'Bronze', color: 'text-theme-warning', bgColor: 'bg-theme-warning-background' },
  silver: { label: 'Silver', color: 'text-theme-text-secondary', bgColor: 'bg-theme-bg-tertiary' },
  gold: { label: 'Gold', color: 'text-theme-warning', bgColor: 'bg-theme-warning-background' },
  platinum: { label: 'Platinum', color: 'text-theme-interactive-primary', bgColor: 'bg-theme-interactive-primary/10' },
};

const TIER_THRESHOLDS: Record<ResellerTier, { referrals: number; revenue: number }> = {
  bronze: { referrals: 0, revenue: 0 },
  silver: { referrals: 5, revenue: 5000 },
  gold: { referrals: 15, revenue: 25000 },
  platinum: { referrals: 50, revenue: 100000 },
};

export const PartnerTierCard: React.FC<PartnerTierCardProps> = ({
  currentTier,
  tierBenefits,
  eligibleForUpgrade,
  nextTier,
  totalReferrals,
  totalRevenueGenerated,
}) => {
  const tierConfig = TIER_CONFIG[currentTier];
  const nextTierConfig = nextTier ? TIER_CONFIG[nextTier] : null;
  const nextTierThresholds = nextTier ? TIER_THRESHOLDS[nextTier] : null;

  const referralProgress = nextTierThresholds
    ? Math.min((totalReferrals / nextTierThresholds.referrals) * 100, 100)
    : 100;
  const revenueProgress = nextTierThresholds
    ? Math.min((totalRevenueGenerated / nextTierThresholds.revenue) * 100, 100)
    : 100;

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Partner Tier</h3>
          <p className="text-sm text-theme-tertiary">Your current partnership level</p>
        </div>
        <span className={`px-4 py-2 rounded-full text-sm font-medium ${tierConfig.bgColor} ${tierConfig.color}`}>
          {tierConfig.label}
        </span>
      </div>

      <div className="space-y-4">
        <div className="flex items-center justify-between py-3 border-b border-theme">
          <span className="text-theme-secondary">Commission Rate</span>
          <span className="text-xl font-bold text-theme-primary">
            {tierBenefits?.commission || 10}%
          </span>
        </div>

        {nextTier && nextTierThresholds && (
          <div className="pt-4">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-medium text-theme-secondary">
                Progress to {nextTierConfig?.label}
              </span>
              {eligibleForUpgrade && (
                <span className="text-xs px-2 py-1 rounded bg-theme-success-background text-theme-success">
                  Eligible!
                </span>
              )}
            </div>

            <div className="space-y-3">
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-tertiary">Referrals</span>
                  <span className="text-theme-secondary">
                    {totalReferrals} / {nextTierThresholds.referrals}
                  </span>
                </div>
                <div className="w-full bg-theme-tertiary rounded-full h-2">
                  <div
                    className="bg-theme-interactive-primary h-2 rounded-full transition-all"
                    style={{ width: `${referralProgress}%` }}
                  />
                </div>
              </div>

              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-tertiary">Revenue Generated</span>
                  <span className="text-theme-secondary">
                    ${totalRevenueGenerated.toLocaleString()} / ${nextTierThresholds.revenue.toLocaleString()}
                  </span>
                </div>
                <div className="w-full bg-theme-tertiary rounded-full h-2">
                  <div
                    className="bg-theme-success h-2 rounded-full transition-all"
                    style={{ width: `${revenueProgress}%` }}
                  />
                </div>
              </div>
            </div>
          </div>
        )}

        {currentTier === 'platinum' && (
          <div className="pt-4 text-center">
            <span className="text-theme-tertiary">
              You've reached the highest partner tier!
            </span>
          </div>
        )}
      </div>
    </Card>
  );
};
