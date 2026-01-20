import React, { useState, useEffect, useCallback } from 'react';
import { PageContainer } from '@/shared/components/layout';
import { LoadingSpinner, EmptyState, Card, Button } from '@/shared/components/ui';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { resellerApi } from '../services/resellerApi';
import { PartnerTierCard } from '../components/PartnerTierCard';
import { CommissionTracker } from '../components/CommissionTracker';
import { PayoutHistory } from '../components/PayoutHistory';
import type { Reseller, ResellerDashboardStats } from '../types';

export const ResellerDashboard: React.FC = () => {
  const { addNotification } = useNotifications();
  const [loading, setLoading] = useState(true);
  const [reseller, setReseller] = useState<Reseller | null>(null);
  const [dashboardStats, setDashboardStats] = useState<ResellerDashboardStats | null>(null);
  const [error, setError] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const resellerResult = await resellerApi.getMyReseller();

      if (!resellerResult.success || !resellerResult.data) {
        setReseller(null);
        setLoading(false);
        return;
      }

      setReseller(resellerResult.data);

      const dashboardResult = await resellerApi.getDashboard(resellerResult.data.id);

      if (dashboardResult.success && dashboardResult.data) {
        setDashboardStats(dashboardResult.data);
      }
    } catch {
      setError('Failed to load reseller data');
      addNotification({ type: 'error', message: 'Failed to load reseller data' });
    } finally {
      setLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleCopyReferralCode = () => {
    if (reseller?.referral_code) {
      navigator.clipboard.writeText(reseller.referral_code);
      addNotification({ type: 'success', message: 'Referral code copied to clipboard' });
    }
  };

  if (loading) {
    return (
      <PageContainer title="Partner Dashboard">
        <div className="flex items-center justify-center h-64">
          <LoadingSpinner size="lg" />
        </div>
      </PageContainer>
    );
  }

  if (error) {
    return (
      <PageContainer title="Partner Dashboard">
        <EmptyState
          icon="alert-circle"
          title="Error Loading Data"
          description={error}
          action={
            <Button onClick={loadData}>Retry</Button>
          }
        />
      </PageContainer>
    );
  }

  if (!reseller) {
    return (
      <PageContainer title="Partner Program">
        <div className="max-w-2xl mx-auto">
          <Card className="p-8 text-center">
            <h2 className="text-2xl font-bold text-theme-primary mb-4">
              Join Our Partner Program
            </h2>
            <p className="text-theme-secondary mb-6">
              Become a Powernode partner and earn commissions by referring customers.
              Earn up to 25% on all referred revenue with our tiered partnership program.
            </p>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
              {['Bronze', 'Silver', 'Gold', 'Platinum'].map((tier, index) => (
                <div key={tier} className="p-4 rounded-lg bg-theme-surface">
                  <p className="font-medium text-theme-primary">{tier}</p>
                  <p className="text-2xl font-bold text-blue-600">{[10, 15, 20, 25][index]}%</p>
                  <p className="text-xs text-theme-tertiary">commission</p>
                </div>
              ))}
            </div>
            <Button variant="primary" onClick={() => {
              // Navigate to application or open modal
              addNotification({ type: 'info', message: 'Partner application coming soon!' });
            }}>
              Apply to Become a Partner
            </Button>
          </Card>
        </div>
      </PageContainer>
    );
  }

  if (reseller.status === 'pending') {
    return (
      <PageContainer title="Partner Program">
        <div className="max-w-2xl mx-auto">
          <Card className="p-8 text-center">
            <div className="w-16 h-16 rounded-full bg-amber-100 flex items-center justify-center mx-auto mb-4">
              <svg className="w-8 h-8 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <h2 className="text-2xl font-bold text-theme-primary mb-4">
              Application Under Review
            </h2>
            <p className="text-theme-secondary mb-6">
              Your partner application is being reviewed. We'll notify you once it's approved.
              This usually takes 1-2 business days.
            </p>
            <p className="text-sm text-theme-tertiary">
              Company: {reseller.company_name}
            </p>
          </Card>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Partner Dashboard"
      actions={
        <Button variant="secondary" onClick={handleCopyReferralCode}>
          Copy Referral Code: {reseller.referral_code}
        </Button>
      }
    >
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-6">
        <Card className="p-6">
          <p className="text-sm text-theme-tertiary mb-1">Total Referrals</p>
          <p className="text-3xl font-bold text-theme-primary">{dashboardStats?.total_referrals || 0}</p>
          <p className="text-sm text-green-600">{dashboardStats?.active_referrals || 0} active</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm text-theme-tertiary mb-1">Revenue Generated</p>
          <p className="text-3xl font-bold text-theme-primary">
            ${(dashboardStats?.total_revenue_generated || 0).toLocaleString()}
          </p>
          <p className="text-sm text-theme-tertiary">all-time</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm text-theme-tertiary mb-1">Total Paid Out</p>
          <p className="text-3xl font-bold text-theme-primary">
            ${(dashboardStats?.total_paid_out || 0).toLocaleString()}
          </p>
          <p className="text-sm text-theme-tertiary">lifetime earnings</p>
        </Card>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <PartnerTierCard
          currentTier={dashboardStats?.tier || reseller.tier}
          tierBenefits={reseller.tier_benefits}
          eligibleForUpgrade={dashboardStats?.eligible_for_upgrade || false}
          nextTier={dashboardStats?.next_tier}
          totalReferrals={dashboardStats?.total_referrals || 0}
          totalRevenueGenerated={dashboardStats?.total_revenue_generated || 0}
        />

        <CommissionTracker
          commissions={dashboardStats?.recent_commissions || []}
          lifetimeEarnings={dashboardStats?.lifetime_earnings || 0}
          pendingPayout={dashboardStats?.pending_payout || 0}
        />
      </div>

      <div className="mt-6">
        <PayoutHistory
          payouts={dashboardStats?.pending_payouts || []}
          pendingPayout={dashboardStats?.pending_payout || 0}
          canRequestPayout={dashboardStats?.can_request_payout || false}
          resellerId={reseller.id}
          onPayoutRequested={loadData}
        />
      </div>
    </PageContainer>
  );
};
