import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { TabNavigation, MobileTabNavigation } from '../../components/ui/TabNavigation';
import { Breadcrumb } from '../../components/ui/Breadcrumb';
import { SubscriptionsPage } from './SubscriptionsPage';
import { BillingPage } from './BillingPage';
import { CustomersPage } from './CustomersPage';

const tabs = [
  { id: 'customers', label: 'Customers', path: '/dashboard/business/customers', icon: '👥' },
  { id: 'subscriptions', label: 'Subscriptions', path: '/dashboard/business/subscriptions', icon: '🔄' },
  { id: 'billing', label: 'Billing', path: '/dashboard/business/billing', icon: '💳' },
  { id: 'invoices', label: 'Invoices', path: '/dashboard/business/invoices', icon: '📄' },
  { id: 'payments', label: 'Payments', path: '/dashboard/business/payments', icon: '💰' },
  { id: 'revenue', label: 'Revenue', path: '/dashboard/business/revenue', icon: '📈' },
];

const InvoicesPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Invoice Management</h2>
        <p className="text-theme-secondary">Manage customer invoices, payment tracking, and billing history.</p>
        
        <div className="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-theme-background p-4 rounded-lg">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Total Invoices</h3>
            <p className="text-2xl font-bold text-theme-primary">0</p>
            <p className="text-xs text-theme-tertiary mt-1">All time</p>
          </div>
          <div className="bg-theme-background p-4 rounded-lg">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Pending Payment</h3>
            <p className="text-2xl font-bold text-theme-warning">$0.00</p>
            <p className="text-xs text-theme-tertiary mt-1">0 invoices</p>
          </div>
          <div className="bg-theme-background p-4 rounded-lg">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Overdue</h3>
            <p className="text-2xl font-bold text-theme-error">$0.00</p>
            <p className="text-xs text-theme-tertiary mt-1">0 invoices</p>
          </div>
        </div>
        
        <div className="mt-6 flex space-x-3">
          <button className="btn-theme btn-theme-primary">
            Generate Invoice
          </button>
          <button className="btn-theme btn-theme-secondary">
            Export Invoices
          </button>
        </div>

        <div className="mt-8">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Recent Invoices</h3>
          <div className="bg-theme-background rounded-lg p-8 text-center">
            <span className="text-4xl">📄</span>
            <p className="text-theme-secondary mt-2">No invoices yet</p>
            <p className="text-theme-tertiary text-sm mt-1">
              Invoices will appear here when you start billing customers
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

const PaymentsPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Payment Processing</h2>
        <p className="text-theme-secondary">Monitor payment transactions, refunds, and gateway activity.</p>
        
        <div className="mt-6 grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="bg-theme-background p-4 rounded-lg">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Successful</h3>
            <p className="text-2xl font-bold text-theme-success">0</p>
            <p className="text-xs text-theme-tertiary mt-1">Today</p>
          </div>
          <div className="bg-theme-background p-4 rounded-lg">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Failed</h3>
            <p className="text-2xl font-bold text-theme-error">0</p>
            <p className="text-xs text-theme-tertiary mt-1">Today</p>
          </div>
          <div className="bg-theme-background p-4 rounded-lg">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Processing</h3>
            <p className="text-2xl font-bold text-theme-warning">0</p>
            <p className="text-xs text-theme-tertiary mt-1">Current</p>
          </div>
          <div className="bg-theme-background p-4 rounded-lg">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Total Volume</h3>
            <p className="text-2xl font-bold text-theme-primary">$0</p>
            <p className="text-xs text-theme-tertiary mt-1">Today</p>
          </div>
        </div>
        
        <div className="mt-8">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Recent Transactions</h3>
          <div className="bg-theme-background rounded-lg p-8 text-center">
            <span className="text-4xl">💳</span>
            <p className="text-theme-secondary mt-2">No transactions yet</p>
            <p className="text-theme-tertiary text-sm mt-1">Payment transactions will appear here</p>
          </div>
        </div>
        
        <div className="mt-6 flex space-x-3">
          <button className="btn-theme btn-theme-primary">
            Process Refund
          </button>
          <button className="btn-theme btn-theme-secondary">
            Export Transactions
          </button>
        </div>
      </div>
    </div>
  );
};

const RevenuePage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Revenue Analytics</h2>
        <p className="text-theme-secondary">Track revenue metrics, growth trends, and financial performance.</p>
        
        <div className="mt-6 grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="bg-theme-background p-4 rounded-lg">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">MRR</h3>
            <p className="text-2xl font-bold text-theme-primary">$0</p>
            <p className="text-xs text-theme-success mt-1">↗ +0%</p>
          </div>
          <div className="bg-theme-background p-4 rounded-lg">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">ARR</h3>
            <p className="text-2xl font-bold text-theme-primary">$0</p>
            <p className="text-xs text-theme-success mt-1">↗ +0%</p>
          </div>
          <div className="bg-theme-background p-4 rounded-lg">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">ARPU</h3>
            <p className="text-2xl font-bold text-theme-primary">$0</p>
            <p className="text-xs text-theme-tertiary mt-1">Per user</p>
          </div>
          <div className="bg-theme-background p-4 rounded-lg">
            <h3 className="text-sm font-medium text-theme-tertiary mb-2">Churn Rate</h3>
            <p className="text-2xl font-bold text-theme-primary">0%</p>
            <p className="text-xs text-theme-success mt-1">↘ Stable</p>
          </div>
        </div>

        <div className="mt-8">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Revenue Breakdown</h3>
          <div className="bg-theme-background rounded-lg p-6">
            <div className="space-y-4">
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">New Subscriptions</span>
                  <span className="text-theme-primary font-medium">$0.00</span>
                </div>
                <div className="w-full bg-theme-surface rounded-full h-2">
                  <div className="bg-theme-success h-2 rounded-full" style={{ width: '0%' }} />
                </div>
              </div>
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Renewals</span>
                  <span className="text-theme-primary font-medium">$0.00</span>
                </div>
                <div className="w-full bg-theme-surface rounded-full h-2">
                  <div className="bg-theme-interactive-primary h-2 rounded-full" style={{ width: '0%' }} />
                </div>
              </div>
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-theme-secondary">Upgrades</span>
                  <span className="text-theme-primary font-medium">$0.00</span>
                </div>
                <div className="w-full bg-theme-surface rounded-full h-2">
                  <div className="bg-theme-interactive-secondary h-2 rounded-full" style={{ width: '0%' }} />
                </div>
              </div>
              <div className="pt-4 border-t border-theme">
                <div className="flex justify-between">
                  <span className="text-theme-primary font-medium">Total Revenue</span>
                  <span className="text-theme-primary font-bold text-lg">$0.00</span>
                </div>
              </div>
            </div>
          </div>
        </div>
        
        <div className="mt-6 flex space-x-3">
          <button className="btn-theme btn-theme-primary">
            View Detailed Reports
          </button>
          <button className="btn-theme btn-theme-secondary">
            Export Data
          </button>
        </div>
      </div>
    </div>
  );
};

export const BusinessManagementPage: React.FC = () => {
  const breadcrumbItems = [
    { label: 'Dashboard', path: '/dashboard', icon: '🏠' },
    { label: 'Business Management', icon: '💼' }
  ];

  return (
    <div className="space-y-6">
      <div>
        <Breadcrumb items={breadcrumbItems} className="mb-4" />
        <h1 className="text-2xl font-bold text-theme-primary">Business Management</h1>
        <p className="text-theme-secondary mt-1">
          Manage your subscription business, customers, and revenue.
        </p>
      </div>

      <div>
        <div className="hidden sm:block">
          <TabNavigation tabs={tabs} basePath="/dashboard/business" />
        </div>
        <MobileTabNavigation tabs={tabs} basePath="/dashboard/business" />
      </div>

      <div>
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard/business/customers" replace />} />
          <Route path="/customers" element={<CustomersPage />} />
          <Route path="/subscriptions" element={<SubscriptionsPage />} />
          <Route path="/billing" element={<BillingPage />} />
          <Route path="/invoices" element={<InvoicesPage />} />
          <Route path="/payments" element={<PaymentsPage />} />
          <Route path="/revenue" element={<RevenuePage />} />
        </Routes>
      </div>
    </div>
  );
};

export default BusinessManagementPage;