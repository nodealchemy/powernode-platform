import React from 'react';

export const AnalyticsPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Analytics</h1>
        <p className="text-gray-600">
          Track your subscription metrics and business performance.
        </p>
      </div>

      {/* Key Metrics Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Monthly Recurring Revenue</h3>
          <p className="text-2xl font-bold text-gray-900">$0.00</p>
          <p className="text-xs text-green-600 mt-1">+0% from last month</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Annual Recurring Revenue</h3>
          <p className="text-2xl font-bold text-gray-900">$0.00</p>
          <p className="text-xs text-green-600 mt-1">+0% from last year</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Customer Lifetime Value</h3>
          <p className="text-2xl font-bold text-gray-900">$0.00</p>
          <p className="text-xs text-gray-500 mt-1">Average per customer</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Churn Rate</h3>
          <p className="text-2xl font-bold text-gray-900">0%</p>
          <p className="text-xs text-gray-500 mt-1">Monthly churn</p>
        </div>
      </div>

      {/* Charts Placeholder */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-lg font-medium text-gray-900 mb-4">Revenue Trend</h3>
          <div className="h-64 bg-gray-100 rounded-md flex items-center justify-center">
            <p className="text-gray-500">Revenue chart will be implemented here</p>
          </div>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-lg font-medium text-gray-900 mb-4">Subscription Growth</h3>
          <div className="h-64 bg-gray-100 rounded-md flex items-center justify-center">
            <p className="text-gray-500">Growth chart will be implemented here</p>
          </div>
        </div>
      </div>

      <div className="bg-white p-6 rounded-lg shadow">
        <h3 className="text-lg font-medium text-gray-900 mb-4">Recent Activity</h3>
        <div className="text-center py-8">
          <p className="text-gray-500">No analytics data available yet.</p>
          <p className="text-sm text-gray-400 mt-2">
            Analytics will appear here once you have active subscriptions.
          </p>
        </div>
      </div>
    </div>
  );
};