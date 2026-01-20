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
    ? 'bg-gray-900 text-white'
    : 'bg-white text-gray-900';

  const cardClasses = isDark
    ? 'bg-gray-800 border-gray-700'
    : 'bg-gray-50 border-gray-200';

  const getStatusBadge = (status: string) => {
    const styles: Record<string, string> = {
      active: 'bg-green-100 text-green-800',
      trialing: 'bg-blue-100 text-blue-800',
      past_due: 'bg-red-100 text-red-800',
      canceled: 'bg-gray-100 text-gray-800',
      paused: 'bg-yellow-100 text-yellow-800',
      paid: 'bg-green-100 text-green-800',
      open: 'bg-yellow-100 text-yellow-800',
      void: 'bg-gray-100 text-gray-500',
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
        <p className={`text-sm ${isDark ? 'text-gray-400' : 'text-gray-600'}`}>
          {customer.email}
        </p>
      </div>

      {/* Tabs */}
      <div className="border-b border-gray-200 dark:border-gray-700 mb-6">
        <nav className="flex space-x-8">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as typeof activeTab)}
              className={`py-3 px-1 border-b-2 font-medium text-sm transition-colors ${
                activeTab === tab.id
                  ? 'border-blue-500 text-blue-600'
                  : `border-transparent ${isDark ? 'text-gray-400 hover:text-gray-200' : 'text-gray-500 hover:text-gray-700'}`
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
            <p className={`text-center py-8 ${isDark ? 'text-gray-400' : 'text-gray-600'}`}>
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
                    <span className={isDark ? 'text-gray-400' : 'text-gray-600'}>Price: </span>
                    {formatPrice(sub.unit_amount * 100, sub.currency)}/{sub.interval}
                  </p>
                  <p>
                    <span className={isDark ? 'text-gray-400' : 'text-gray-600'}>
                      {sub.cancel_at_period_end ? 'Cancels on: ' : 'Renews on: '}
                    </span>
                    {formatDate(sub.current_period_end)}
                  </p>
                </div>
                <div className="mt-4 flex gap-2">
                  {sub.status === 'active' && !sub.cancel_at_period_end && (
                    <button
                      onClick={() => onCancelSubscription?.(sub.id)}
                      className="px-4 py-2 text-sm text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                    >
                      Cancel Subscription
                    </button>
                  )}
                  {sub.cancel_at_period_end && (
                    <button
                      onClick={() => onResumeSubscription?.(sub.id)}
                      className="px-4 py-2 text-sm text-blue-600 hover:bg-blue-50 rounded-lg transition-colors"
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
            <p className={`text-center py-8 ${isDark ? 'text-gray-400' : 'text-gray-600'}`}>
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
                  <p className={`text-sm ${isDark ? 'text-gray-400' : 'text-gray-600'}`}>
                    {formatDate(invoice.due_date)}
                  </p>
                </div>
                <div className="flex items-center gap-4">
                  <p className="font-medium">{formatPrice(invoice.total_cents, invoice.currency)}</p>
                  {getStatusBadge(invoice.status)}
                  {invoice.invoice_pdf_url && (
                    <button
                      onClick={() => onDownloadInvoice?.(invoice.id)}
                      className="text-blue-600 hover:text-blue-700"
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
            <p className={`text-center py-8 ${isDark ? 'text-gray-400' : 'text-gray-600'}`}>
              No payment methods
            </p>
          ) : (
            paymentMethods.map((method) => (
              <div key={method.id} className={`p-4 rounded-lg border flex items-center gap-4 ${cardClasses}`}>
                <div className="w-12 h-8 bg-gray-200 rounded flex items-center justify-center">
                  <span className="text-xs font-bold text-gray-600">{method.brand}</span>
                </div>
                <div className="flex-1">
                  <p className="font-medium">
                    {method.brand} ending in {method.last4}
                  </p>
                  <p className={`text-sm ${isDark ? 'text-gray-400' : 'text-gray-600'}`}>
                    Expires {method.exp_month}/{method.exp_year}
                  </p>
                </div>
                {method.is_default && (
                  <span className="text-xs text-green-600 font-medium">Default</span>
                )}
              </div>
            ))
          )}
          <button
            onClick={onUpdatePaymentMethod}
            className="w-full py-3 px-4 border border-gray-300 rounded-lg text-sm font-medium hover:bg-gray-50 transition-colors"
          >
            Update Payment Method
          </button>
        </div>
      )}
    </div>
  );
};

export default CustomerPortal;
