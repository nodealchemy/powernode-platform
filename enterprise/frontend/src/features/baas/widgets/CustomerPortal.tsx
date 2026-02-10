import React, { useState } from 'react';

interface Subscription {
  id: string;
  plan_name: string;
  status: string;
  current_period_end: string;
  cancel_at_period_end: boolean;
  unit_amount: number;
  currency: string;
  interval: string;
}

interface Invoice {
  id: string;
  number: string;
  status: string;
  total_cents: number;
  currency: string;
  due_date: string;
  invoice_pdf_url?: string;
}

interface PaymentMethod {
  id: string;
  type: string;
  last4: string;
  exp_month: number;
  exp_year: number;
  brand: string;
  is_default: boolean;
}

interface CustomerPortalProps {
  customer: {
    name: string;
    email: string;
  };
  subscriptions: Subscription[];
  invoices: Invoice[];
  paymentMethods: PaymentMethod[];
  onCancelSubscription?: (subscriptionId: string) => void;
  onResumeSubscription?: (subscriptionId: string) => void;
  onUpdatePaymentMethod?: () => void;
  onDownloadInvoice?: (invoiceId: string) => void;
  theme?: 'light' | 'dark';
}

const formatPrice = (cents: number, currency: string): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency.toUpperCase(),
  }).format(cents / 100);
};

const formatDate = (dateStr: string): string => {
  return new Date(dateStr).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
};

/**
 * Embeddable Customer Portal Widget
 *
 * Allows customers to manage their subscription, view invoices,
 * and update payment methods.
 */
export const CustomerPortal: React.FC<CustomerPortalProps> = ({
  customer,
  subscriptions,
  invoices,
  paymentMethods,
  onCancelSubscription,
  onResumeSubscription,
  onUpdatePaymentMethod,
  onDownloadInvoice,
  theme = 'light',
}) => {
  const [activeTab, setActiveTab] = useState<'subscription' | 'invoices' | 'payment'>('subscription');
  const isDark = theme === 'dark';

  const baseClasses = isDark
    ? 'bg-theme-background text-white'
    : 'bg-white text-theme-primary';

  const cardClasses = 'bg-theme-surface border-theme-border';

  const getStatusBadge = (status: string) => {
    const styles: Record<string, string> = {
      active: 'bg-theme-success/20 text-theme-success',
      trialing: 'bg-theme-info/20 text-theme-info',
      past_due: 'bg-theme-danger/20 text-theme-danger',
      canceled: 'bg-theme-surface text-theme-primary',
      paused: 'bg-theme-warning/20 text-theme-warning',
      paid: 'bg-theme-success/20 text-theme-success',
      open: 'bg-theme-warning/20 text-theme-warning',
      void: 'bg-theme-surface text-theme-muted',
    };
    return (
      <span className={`px-2 py-1 rounded-full text-xs font-medium ${styles[status] || styles.active}`}>
        {status.charAt(0).toUpperCase() + status.slice(1).replace('_', ' ')}
      </span>
    );
  };

  const tabs = [
    { id: 'subscription', label: 'Subscription' },
    { id: 'invoices', label: 'Invoices' },
    { id: 'payment', label: 'Payment Method' },
  ];

  return (
    <div className={`p-6 rounded-xl ${baseClasses}`}>
      {/* Header */}
      <div className="mb-6">
        <h2 className="text-xl font-bold">{customer.name}</h2>
        <p className="text-sm text-theme-muted">
          {customer.email}
        </p>
      </div>

      {/* Tabs */}
      <div className="border-b border-theme mb-6">
        <nav className="flex space-x-8">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as typeof activeTab)}
              className={`py-3 px-1 border-b-2 font-medium text-sm transition-colors ${
                activeTab === tab.id
                  ? 'border-theme-info text-theme-info'
                  : 'border-transparent text-theme-muted hover:text-theme-secondary'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Subscription Tab */}
      {activeTab === 'subscription' && (
        <div className="space-y-4">
          {subscriptions.length === 0 ? (
            <p className="text-center py-8 text-theme-muted">
              No active subscriptions
            </p>
          ) : (
            subscriptions.map((sub) => (
              <div key={sub.id} className={`p-4 rounded-lg border ${cardClasses}`}>
                <div className="flex items-center justify-between mb-3">
                  <h3 className="font-semibold">{sub.plan_name}</h3>
                  {getStatusBadge(sub.status)}
                </div>
                <div className="space-y-2 text-sm">
                  <p>
                    <span className="text-theme-muted">Price: </span>
                    {formatPrice(sub.unit_amount * 100, sub.currency)}/{sub.interval}
                  </p>
                  <p>
                    <span className="text-theme-muted">
                      {sub.cancel_at_period_end ? 'Cancels on: ' : 'Renews on: '}
                    </span>
                    {formatDate(sub.current_period_end)}
                  </p>
                </div>
                <div className="mt-4 flex gap-2">
                  {sub.status === 'active' && !sub.cancel_at_period_end && (
                    <button
                      onClick={() => onCancelSubscription?.(sub.id)}
                      className="px-4 py-2 text-sm text-theme-danger hover:bg-theme-danger/10 rounded-lg transition-colors"
                    >
                      Cancel Subscription
                    </button>
                  )}
                  {sub.cancel_at_period_end && (
                    <button
                      onClick={() => onResumeSubscription?.(sub.id)}
                      className="px-4 py-2 text-sm text-theme-info hover:bg-theme-info/10 rounded-lg transition-colors"
                    >
                      Resume Subscription
                    </button>
                  )}
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {/* Invoices Tab */}
      {activeTab === 'invoices' && (
        <div className="space-y-2">
          {invoices.length === 0 ? (
            <p className="text-center py-8 text-theme-muted">
              No invoices
            </p>
          ) : (
            invoices.map((invoice) => (
              <div
                key={invoice.id}
                className={`p-4 rounded-lg border flex items-center justify-between ${cardClasses}`}
              >
                <div>
                  <p className="font-medium">{invoice.number}</p>
                  <p className="text-sm text-theme-muted">
                    {formatDate(invoice.due_date)}
                  </p>
                </div>
                <div className="flex items-center gap-4">
                  <p className="font-medium">{formatPrice(invoice.total_cents, invoice.currency)}</p>
                  {getStatusBadge(invoice.status)}
                  {invoice.invoice_pdf_url && (
                    <button
                      onClick={() => onDownloadInvoice?.(invoice.id)}
                      className="text-theme-info hover:text-theme-info"
                    >
                      <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
                      </svg>
                    </button>
                  )}
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {/* Payment Method Tab */}
      {activeTab === 'payment' && (
        <div className="space-y-4">
          {paymentMethods.length === 0 ? (
            <p className="text-center py-8 text-theme-muted">
              No payment methods
            </p>
          ) : (
            paymentMethods.map((method) => (
              <div key={method.id} className={`p-4 rounded-lg border flex items-center gap-4 ${cardClasses}`}>
                <div className="w-12 h-8 bg-theme-border rounded flex items-center justify-center">
                  <span className="text-xs font-bold text-theme-muted">{method.brand}</span>
                </div>
                <div className="flex-1">
                  <p className="font-medium">
                    {method.brand} ending in {method.last4}
                  </p>
                  <p className="text-sm text-theme-muted">
                    Expires {method.exp_month}/{method.exp_year}
                  </p>
                </div>
                {method.is_default && (
                  <span className="text-xs text-theme-success font-medium">Default</span>
                )}
              </div>
            ))
          )}
          <button
            onClick={onUpdatePaymentMethod}
            className="w-full py-3 px-4 border border-theme rounded-lg text-sm font-medium hover:bg-theme-surface transition-colors"
          >
            Update Payment Method
          </button>
        </div>
      )}
    </div>
  );
};

export default CustomerPortal;
