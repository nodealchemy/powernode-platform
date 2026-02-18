import React, { useState } from 'react';
import { Card, Badge, Button, Modal } from '@/shared/components/ui';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { resellerApi } from '../services/resellerApi';
import { formatDate } from '@/shared/utils/formatters';
import type { ResellerPayout } from '../types';

interface PayoutHistoryProps {
  payouts: ResellerPayout[];
  pendingPayout: number;
  canRequestPayout: boolean;
  resellerId: string;
  onPayoutRequested: () => void;
}

const STATUS_CONFIG: Record<string, { label: string; variant: 'success' | 'warning' | 'danger' | 'default' }> = {
  pending: { label: 'Pending', variant: 'warning' },
  processing: { label: 'Processing', variant: 'default' },
  completed: { label: 'Completed', variant: 'success' },
  failed: { label: 'Failed', variant: 'danger' },
  cancelled: { label: 'Cancelled', variant: 'danger' },
};

const METHOD_LABELS: Record<string, string> = {
  bank_transfer: 'Bank Transfer',
  paypal: 'PayPal',
  stripe: 'Stripe',
  check: 'Check',
  wire: 'Wire Transfer',
};

export const PayoutHistory: React.FC<PayoutHistoryProps> = ({
  payouts,
  pendingPayout,
  canRequestPayout,
  resellerId,
  onPayoutRequested,
}) => {
  const { addNotification } = useNotifications();
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [payoutAmount, setPayoutAmount] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
    }).format(amount);
  };


  const handleRequestPayout = async () => {
    const amount = parseFloat(payoutAmount);

    if (isNaN(amount) || amount <= 0) {
      addNotification({ type: 'error', message: 'Please enter a valid amount' });
      return;
    }

    if (amount > pendingPayout) {
      addNotification({ type: 'error', message: 'Amount exceeds available balance' });
      return;
    }

    if (amount < 50) {
      addNotification({ type: 'error', message: 'Minimum payout amount is $50' });
      return;
    }

    setIsSubmitting(true);
    try {
      const result = await resellerApi.requestPayout(resellerId, amount);

      if (result.success) {
        addNotification({ type: 'success', message: 'Payout request submitted successfully' });
        setIsModalOpen(false);
        setPayoutAmount('');
        onPayoutRequested();
      } else {
        addNotification({ type: 'error', message: result.error || 'Failed to request payout' });
      }
    } catch (_error) {
      addNotification({ type: 'error', message: 'An error occurred' });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <>
      <Card className="p-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">Payout History</h3>
            <p className="text-sm text-theme-tertiary">Your payout requests and history</p>
          </div>
          <Button
            variant="primary"
            onClick={() => setIsModalOpen(true)}
            disabled={!canRequestPayout}
          >
            Request Payout
          </Button>
        </div>

        <div className="p-4 rounded-lg bg-theme-surface mb-6">
          <p className="text-sm text-theme-tertiary mb-1">Available for Payout</p>
          <p className="text-2xl font-bold text-theme-success">{formatCurrency(pendingPayout)}</p>
          {!canRequestPayout && pendingPayout < 50 && (
            <p className="text-xs text-theme-warning mt-1">
              Minimum payout is $50
            </p>
          )}
        </div>

        {payouts.length === 0 ? (
          <p className="text-center text-theme-tertiary py-8">
            No payout history yet.
          </p>
        ) : (
          <div className="space-y-3">
            {payouts.map((payout) => {
              const statusConfig = STATUS_CONFIG[payout.status] || STATUS_CONFIG.pending;

              return (
                <div
                  key={payout.id}
                  className="flex items-center justify-between p-4 rounded-lg bg-theme-surface"
                >
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <span className="font-medium text-theme-primary">
                        {formatCurrency(payout.net_amount)}
                      </span>
                      <Badge variant={statusConfig.variant} size="sm">
                        {statusConfig.label}
                      </Badge>
                    </div>
                    <div className="flex items-center gap-2 text-sm text-theme-tertiary">
                      <span>{payout.payout_reference}</span>
                      <span>•</span>
                      <span>{METHOD_LABELS[payout.payout_method] || payout.payout_method}</span>
                    </div>
                  </div>

                  <div className="text-right text-sm text-theme-tertiary">
                    <p>Requested: {formatDate(payout.requested_at)}</p>
                    {payout.completed_at && (
                      <p className="text-theme-success">Paid: {formatDate(payout.completed_at)}</p>
                    )}
                    {payout.fee > 0 && (
                      <p className="text-xs">Fee: {formatCurrency(payout.fee)}</p>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Card>

      <Modal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        title="Request Payout"
      >
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-2">
              Payout Amount
            </label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-theme-tertiary">$</span>
              <input
                type="number"
                min="50"
                max={pendingPayout}
                step="0.01"
                value={payoutAmount}
                onChange={(e) => setPayoutAmount(e.target.value)}
                placeholder="Enter amount"
                className="w-full pl-8 pr-4 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            <p className="text-sm text-theme-tertiary mt-2">
              Available: {formatCurrency(pendingPayout)} | Minimum: $50
            </p>
          </div>

          <div className="flex justify-end gap-3 pt-4">
            <Button variant="secondary" onClick={() => setIsModalOpen(false)}>
              Cancel
            </Button>
            <Button
              variant="primary"
              onClick={handleRequestPayout}
              disabled={isSubmitting || !payoutAmount}
            >
              {isSubmitting ? 'Requesting...' : 'Request Payout'}
            </Button>
          </div>
        </div>
      </Modal>
    </>
  );
};
