import React, { useState, useEffect } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import publisherApi from '../services/publisherApi';
import type { Transaction, StripeStatusResponse } from '../types';

interface PayoutManagerProps {
  publisherId: string;
  pendingPayout: number;
  payoutEnabled: boolean;
  payouts: Transaction[];
  onPayoutRequested?: () => void;
}

const formatCurrency = (value: number): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(value);
};

const formatDate = (dateStr: string): string => {
  return new Date(dateStr).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
};

export const PayoutManager: React.FC<PayoutManagerProps> = ({
  publisherId,
  pendingPayout,
  payoutEnabled,
  payouts,
  onPayoutRequested,
}) => {
  const { showNotification } = useNotifications();
  const [isRequestModalOpen, setIsRequestModalOpen] = useState(false);
  const [isSetupModalOpen, setIsSetupModalOpen] = useState(false);
  const [payoutAmount, setPayoutAmount] = useState<string>('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [stripeStatus, setStripeStatus] = useState<StripeStatusResponse | null>(null);

  useEffect(() => {
    const fetchStripeStatus = async () => {
      try {
        const response = await publisherApi.getStripeStatus(publisherId);
        setStripeStatus(response.data);
      } catch {
        // Stripe not connected
      }
    };
    fetchStripeStatus();
  }, [publisherId]);

  const handleRequestPayout = async () => {
    const amount = parseFloat(payoutAmount);
    if (isNaN(amount) || amount <= 0) {
      showNotification('Please enter a valid amount', 'error');
      return;
    }
    if (amount > pendingPayout) {
      showNotification('Amount exceeds available balance', 'error');
      return;
    }

    setIsSubmitting(true);
    try {
      const response = await publisherApi.requestPayout(publisherId, { amount });
      showNotification(response.message, 'success');
      setIsRequestModalOpen(false);
      setPayoutAmount('');
      onPayoutRequested?.();
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'Failed to request payout';
      showNotification(message, 'error');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleStripeSetup = async () => {
    setIsSubmitting(true);
    try {
      const returnUrl = `${window.location.origin}/ai/publisher/dashboard?stripe=success`;
      const refreshUrl = `${window.location.origin}/ai/publisher/dashboard?stripe=refresh`;

      const response = await publisherApi.setupStripeConnect(publisherId, {
        return_url: returnUrl,
        refresh_url: refreshUrl,
      });

      // Redirect to Stripe onboarding
      window.location.href = response.data.onboarding_url;
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'Failed to setup Stripe';
      showNotification(message, 'error');
    } finally {
      setIsSubmitting(false);
    }
  };

  const getStatusBadge = (status: string) => {
    const styles: Record<string, string> = {
      completed: 'bg-theme-success-background text-theme-success',
      pending: 'bg-theme-warning-background text-theme-warning',
      failed: 'bg-theme-error-background text-theme-error',
    };
    return (
      <span className={`px-2 py-1 rounded-full text-xs font-medium ${styles[status] || 'bg-theme-bg-tertiary text-theme-text-secondary'}`}>
        {status.charAt(0).toUpperCase() + status.slice(1)}
      </span>
    );
  };

  return (
    <div className="space-y-6">
      {/* Payout Summary */}
      <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-theme-text-primary">
            Payout Management
          </h3>
          {payoutEnabled ? (
            <span className="flex items-center text-theme-success text-sm">
              <svg className="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
              </svg>
              Stripe Connected
            </span>
          ) : (
            <Button
              variant="outline"
              size="sm"
              onClick={() => setIsSetupModalOpen(true)}
            >
              Setup Stripe
            </Button>
          )}
        </div>

        <div className="grid grid-cols-2 gap-4 mb-6">
          <div className="bg-theme-bg-secondary rounded-lg p-4">
            <p className="text-sm text-theme-text-secondary">Available for Payout</p>
            <p className="text-2xl font-bold text-theme-text-primary">
              {formatCurrency(pendingPayout)}
            </p>
          </div>
          <div className="bg-theme-bg-secondary rounded-lg p-4">
            <p className="text-sm text-theme-text-secondary">Stripe Status</p>
            <p className="text-lg font-medium text-theme-text-primary">
              {stripeStatus?.status || 'Not Connected'}
            </p>
          </div>
        </div>

        <Button
          variant="primary"
          onClick={() => setIsRequestModalOpen(true)}
          disabled={!payoutEnabled || pendingPayout <= 0}
          className="w-full"
        >
          Request Payout
        </Button>
        {!payoutEnabled && (
          <p className="text-sm text-theme-text-secondary mt-2 text-center">
            Connect your Stripe account to enable payouts
          </p>
        )}
      </div>

      {/* Payout History */}
      <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
        <h3 className="text-lg font-semibold text-theme-text-primary mb-4">
          Payout History
        </h3>
        {payouts.length === 0 ? (
          <p className="text-theme-text-secondary text-center py-8">
            No payouts yet
          </p>
        ) : (
          <div className="space-y-3">
            {payouts.map((payout) => (
              <div
                key={payout.id}
                className="flex items-center justify-between p-4 bg-theme-bg-secondary rounded-lg"
              >
                <div>
                  <p className="font-medium text-theme-text-primary">
                    {formatCurrency(payout.publisher_amount)}
                  </p>
                  <p className="text-sm text-theme-text-secondary">
                    {formatDate(payout.created_at)}
                  </p>
                </div>
                {getStatusBadge(payout.status)}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Request Payout Modal */}
      <Modal
        isOpen={isRequestModalOpen}
        onClose={() => setIsRequestModalOpen(false)}
        title="Request Payout"
      >
        <div className="space-y-4">
          <div>
            <p className="text-sm text-theme-text-secondary mb-2">
              Available balance: {formatCurrency(pendingPayout)}
            </p>
            <Input
              type="number"
              label="Payout Amount"
              value={payoutAmount}
              onChange={(e) => setPayoutAmount(e.target.value)}
              placeholder="0.00"
              min="0"
              max={pendingPayout}
              step="0.01"
            />
          </div>
          <div className="flex justify-end gap-3">
            <Button
              variant="secondary"
              onClick={() => setIsRequestModalOpen(false)}
            >
              Cancel
            </Button>
            <Button
              variant="primary"
              onClick={handleRequestPayout}
              loading={isSubmitting}
            >
              Request Payout
            </Button>
          </div>
        </div>
      </Modal>

      {/* Stripe Setup Modal */}
      <Modal
        isOpen={isSetupModalOpen}
        onClose={() => setIsSetupModalOpen(false)}
        title="Setup Stripe Connect"
      >
        <div className="space-y-4">
          <p className="text-theme-text-secondary">
            Connect your Stripe account to receive payouts from your template sales.
            You will be redirected to Stripe to complete the onboarding process.
          </p>
          <div className="bg-theme-bg-secondary rounded-lg p-4">
            <h4 className="font-medium text-theme-text-primary mb-2">
              Benefits of Stripe Connect:
            </h4>
            <ul className="list-disc list-inside text-sm text-theme-text-secondary space-y-1">
              <li>Instant payouts to your bank account</li>
              <li>Secure payment processing</li>
              <li>Transparent earnings tracking</li>
              <li>Support for multiple currencies</li>
            </ul>
          </div>
          <div className="flex justify-end gap-3">
            <Button
              variant="secondary"
              onClick={() => setIsSetupModalOpen(false)}
            >
              Cancel
            </Button>
            <Button
              variant="primary"
              onClick={handleStripeSetup}
              loading={isSubmitting}
            >
              Connect with Stripe
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  );
};

export default PayoutManager;
