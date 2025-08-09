import React from 'react';
import { Routes, Route } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { DashboardLayout } from '../../components/dashboard/DashboardLayout';

// Import all dashboard pages
import { AnalyticsPage } from './AnalyticsPage';
import { SubscriptionsPage } from './SubscriptionsPage';
import { CustomersPage } from './CustomersPage';
import { PlansPage } from './PlansPage';
import { BillingPage } from './BillingPage';
import { SettingsPage } from './SettingsPage';
import { AdminSettingsPage } from './AdminSettingsPage';
import PaymentGatewaysPage from './PaymentGatewaysPage';
import { FormThemeTestPage } from '../../components/test/FormThemeTestPage';

// Dashboard overview page
const DashboardOverview: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  
  return (
    <div className="space-y-6">
      {/* Header Section */}
      <div className="bg-theme-background-secondary p-6 rounded-xl border border-theme-light">
        <h1 className="text-3xl font-bold text-theme-primary mb-2">
          Welcome back, {user?.firstName}! 👋
        </h1>
        <p className="text-theme-secondary text-lg">
          Here's an overview of your account activity and system status.
        </p>
      </div>

      {/* Key Metrics Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="card-theme p-6 transition-theme-fast hover:shadow-theme-md">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-sm font-medium text-theme-tertiary mb-1">Total Revenue</h3>
              <p className="text-3xl font-bold text-theme-primary">$0.00</p>
              <p className="text-xs text-theme-success mt-1">↗ +0% from last month</p>
            </div>
            <div className="h-12 w-12 bg-theme-success rounded-xl flex items-center justify-center bg-opacity-10">
              <span className="text-2xl">💰</span>
            </div>
          </div>
        </div>

        <div className="card-theme p-6 transition-theme-fast hover:shadow-theme-md">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-sm font-medium text-theme-tertiary mb-1">Active Subscriptions</h3>
              <p className="text-3xl font-bold text-theme-primary">0</p>
              <p className="text-xs text-theme-info mt-1">Ready to grow</p>
            </div>
            <div className="h-12 w-12 bg-theme-info rounded-xl flex items-center justify-center bg-opacity-10">
              <span className="text-2xl">📊</span>
            </div>
          </div>
        </div>

        <div className="card-theme p-6 transition-theme-fast hover:shadow-theme-md">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-sm font-medium text-theme-tertiary mb-1">Monthly Growth</h3>
              <p className="text-3xl font-bold text-theme-primary">0%</p>
              <p className="text-xs text-theme-warning mt-1">Start your journey</p>
            </div>
            <div className="h-12 w-12 bg-theme-warning rounded-xl flex items-center justify-center bg-opacity-10">
              <span className="text-2xl">📈</span>
            </div>
          </div>
        </div>

        <div className="card-theme p-6 transition-theme-fast hover:shadow-theme-md">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-sm font-medium text-theme-tertiary mb-1">System Health</h3>
              <p className="text-3xl font-bold text-theme-success">100%</p>
              <p className="text-xs text-theme-success mt-1">All systems operational</p>
            </div>
            <div className="h-12 w-12 bg-theme-success rounded-xl flex items-center justify-center bg-opacity-10">
              <span className="text-2xl">✅</span>
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Getting Started Card */}
        <div className="card-theme-elevated p-6">
          <div className="flex items-center justify-between mb-6">
            <h3 className="text-xl font-semibold text-theme-primary">
              Getting Started
            </h3>
            <span className="bg-theme-info text-theme-on-primary px-3 py-1 rounded-full text-xs font-medium bg-opacity-10 text-theme-info">
              2 of 4 complete
            </span>
          </div>
          
          <div className="space-y-4">
            <div className="flex items-start space-x-3">
              <div className="flex-shrink-0 mt-1">
                <div className="h-5 w-5 bg-theme-success rounded-full flex items-center justify-center">
                  <span className="text-white text-xs">✓</span>
                </div>
              </div>
              <div className="flex-1">
                <p className="text-sm font-medium text-theme-primary">Account created successfully</p>
                <p className="text-xs text-theme-tertiary mt-1">Your Powernode account is ready to use</p>
              </div>
            </div>

            <div className="flex items-start space-x-3">
              <div className="flex-shrink-0 mt-1">
                <div className="h-5 w-5 bg-theme-success rounded-full flex items-center justify-center">
                  <span className="text-white text-xs">✓</span>
                </div>
              </div>
              <div className="flex-1">
                <p className="text-sm font-medium text-theme-primary">Email verification completed</p>
                <p className="text-xs text-theme-tertiary mt-1">Your email address has been verified</p>
              </div>
            </div>

            <div className="flex items-start space-x-3">
              <div className="flex-shrink-0 mt-1">
                <div className="h-5 w-5 bg-theme-warning rounded-full flex items-center justify-center">
                  <span className="text-white text-xs">!</span>
                </div>
              </div>
              <div className="flex-1">
                <p className="text-sm font-medium text-theme-primary">Set up your first subscription plan</p>
                <p className="text-xs text-theme-tertiary mt-1">Create plans to start accepting payments</p>
                <button className="btn-theme btn-theme-primary mt-2 text-xs px-3 py-1">
                  Create Plan
                </button>
              </div>
            </div>

            <div className="flex items-start space-x-3">
              <div className="flex-shrink-0 mt-1">
                <div className="h-5 w-5 bg-theme-background-tertiary border border-theme rounded-full flex items-center justify-center">
                  <span className="text-theme-tertiary text-xs">○</span>
                </div>
              </div>
              <div className="flex-1">
                <p className="text-sm font-medium text-theme-tertiary">Configure payment methods</p>
                <p className="text-xs text-theme-quaternary mt-1">Set up Stripe or PayPal integration</p>
                <button className="btn-theme btn-theme-secondary mt-2 text-xs px-3 py-1">
                  Configure Payments
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* Quick Actions Card */}
        <div className="card-theme-elevated p-6">
          <h3 className="text-xl font-semibold text-theme-primary mb-6">
            Quick Actions
          </h3>
          
          <div className="grid grid-cols-1 gap-3">
            <button className="btn-theme btn-theme-secondary flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover">
              <div className="flex items-center space-x-3">
                <span className="text-2xl">👥</span>
                <div>
                  <p className="font-medium text-theme-primary">Manage Customers</p>
                  <p className="text-xs text-theme-tertiary">View and organize your customer base</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </button>

            <button className="btn-theme btn-theme-secondary flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover">
              <div className="flex items-center space-x-3">
                <span className="text-2xl">📊</span>
                <div>
                  <p className="font-medium text-theme-primary">View Analytics</p>
                  <p className="text-xs text-theme-tertiary">Track revenue and growth metrics</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </button>

            <button className="btn-theme btn-theme-secondary flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover">
              <div className="flex items-center space-x-3">
                <span className="text-2xl">💳</span>
                <div>
                  <p className="font-medium text-theme-primary">Payment Gateways</p>
                  <p className="text-xs text-theme-tertiary">Configure Stripe and PayPal</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </button>

            <button className="btn-theme btn-theme-secondary flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover">
              <div className="flex items-center space-x-3">
                <span className="text-2xl">⚙️</span>
                <div>
                  <p className="font-medium text-theme-primary">Account Settings</p>
                  <p className="text-xs text-theme-tertiary">Customize your account preferences</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </button>
          </div>
        </div>
      </div>

      {/* System Status Alert */}
      <div className="alert-theme alert-theme-success">
        <div className="flex items-center">
          <span className="text-2xl mr-3">🚀</span>
          <div>
            <h4 className="font-medium text-theme-success">Powernode Platform Ready</h4>
            <p className="text-sm text-theme-success mt-1">
              Your subscription platform is set up and ready for configuration. Start by creating your first subscription plan!
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export const DashboardPage: React.FC = () => {
  return (
    <DashboardLayout>
      <Routes>
        <Route path="/" element={<DashboardOverview />} />
        <Route path="/analytics" element={<AnalyticsPage />} />
        <Route path="/subscriptions" element={<SubscriptionsPage />} />
        <Route path="/customers" element={<CustomersPage />} />
        <Route path="/plans" element={<PlansPage />} />
        <Route path="/billing" element={<BillingPage />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="/admin-settings" element={<AdminSettingsPage />} />
        <Route path="/payment-gateways" element={<PaymentGatewaysPage />} />
        <Route path="/form-test" element={<FormThemeTestPage />} />
      </Routes>
    </DashboardLayout>
  );
};