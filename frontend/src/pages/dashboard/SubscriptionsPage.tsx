import React from 'react';

export const SubscriptionsPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Subscriptions</h1>
          <p className="text-gray-600">
            Manage subscription plans and customer subscriptions.
          </p>
        </div>
        <button className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors">
          Create Plan
        </button>
      </div>

      {/* Subscription Plans */}
      <div className="bg-white shadow rounded-lg">
        <div className="px-6 py-4 border-b border-gray-200">
          <h3 className="text-lg font-medium text-gray-900">Available Plans</h3>
        </div>
        <div className="p-6">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {/* Starter Plan */}
            <div className="border border-gray-200 rounded-lg p-6">
              <h4 className="text-lg font-semibold text-gray-900">Starter</h4>
              <p className="text-3xl font-bold text-gray-900 mt-2">$9.99<span className="text-sm font-normal text-gray-500">/month</span></p>
              <p className="text-gray-500 mt-2">Perfect for individuals and small teams</p>
              <ul className="mt-4 space-y-2 text-sm text-gray-600">
                <li>• 5 users</li>
                <li>• 10 projects</li>
                <li>• 5GB storage</li>
                <li>• Email support</li>
              </ul>
              <button className="mt-6 w-full bg-gray-100 text-gray-900 py-2 px-4 rounded-md hover:bg-gray-200 transition-colors">
                Manage
              </button>
            </div>

            {/* Professional Plan */}
            <div className="border border-gray-200 rounded-lg p-6">
              <h4 className="text-lg font-semibold text-gray-900">Professional</h4>
              <p className="text-3xl font-bold text-gray-900 mt-2">$29.99<span className="text-sm font-normal text-gray-500">/month</span></p>
              <p className="text-gray-500 mt-2">For growing teams with advanced needs</p>
              <ul className="mt-4 space-y-2 text-sm text-gray-600">
                <li>• 25 users</li>
                <li>• 100 projects</li>
                <li>• 50GB storage</li>
                <li>• Priority support</li>
              </ul>
              <button className="mt-6 w-full bg-gray-100 text-gray-900 py-2 px-4 rounded-md hover:bg-gray-200 transition-colors">
                Manage
              </button>
            </div>

            {/* Enterprise Plan */}
            <div className="border border-gray-200 rounded-lg p-6">
              <h4 className="text-lg font-semibold text-gray-900">Enterprise</h4>
              <p className="text-3xl font-bold text-gray-900 mt-2">$99.99<span className="text-sm font-normal text-gray-500">/month</span></p>
              <p className="text-gray-500 mt-2">For large organizations</p>
              <ul className="mt-4 space-y-2 text-sm text-gray-600">
                <li>• Unlimited users</li>
                <li>• Unlimited projects</li>
                <li>• 500GB storage</li>
                <li>• Dedicated support</li>
              </ul>
              <button className="mt-6 w-full bg-gray-100 text-gray-900 py-2 px-4 rounded-md hover:bg-gray-200 transition-colors">
                Manage
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Active Subscriptions */}
      <div className="bg-white shadow rounded-lg">
        <div className="px-6 py-4 border-b border-gray-200">
          <h3 className="text-lg font-medium text-gray-900">Active Subscriptions</h3>
        </div>
        <div className="p-6">
          <div className="text-center py-8">
            <p className="text-gray-500">No active subscriptions found.</p>
            <p className="text-sm text-gray-400 mt-2">
              Active customer subscriptions will appear here.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};