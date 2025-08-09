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

// Dashboard overview page
const DashboardOverview: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">
          Welcome back, {user?.firstName}!
        </h1>
        <p className="text-gray-600">
          Here's an overview of your account activity.
        </p>
      </div>

      {/* Dashboard content will be implemented in future iterations */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Total Revenue</h3>
          <p className="text-2xl font-bold text-gray-900">$0.00</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Active Subscriptions</h3>
          <p className="text-2xl font-bold text-gray-900">0</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Monthly Growth</h3>
          <p className="text-2xl font-bold text-gray-900">0%</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Churn Rate</h3>
          <p className="text-2xl font-bold text-gray-900">0%</p>
        </div>
      </div>

      <div className="bg-white p-6 rounded-lg shadow">
        <h3 className="text-lg font-medium text-gray-900 mb-4">
          Getting Started
        </h3>
        <div className="space-y-3">
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <div className="h-2 w-2 bg-green-500 rounded-full"></div>
            </div>
            <p className="ml-3 text-sm text-gray-600">
              Account created successfully
            </p>
          </div>
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <div className="h-2 w-2 bg-yellow-500 rounded-full"></div>
            </div>
            <p className="ml-3 text-sm text-gray-600">
              Set up your first subscription plan
            </p>
          </div>
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <div className="h-2 w-2 bg-gray-300 rounded-full"></div>
            </div>
            <p className="ml-3 text-sm text-gray-600">
              Configure payment methods
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
      </Routes>
    </DashboardLayout>
  );
};