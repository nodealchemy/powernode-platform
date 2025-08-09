import React, { useState, useEffect } from 'react';
import { billingApi, BillingOverview, Invoice, PaymentMethod } from '../../services/billingApi';

export const BillingPage: React.FC = () => {
  const [overview, setOverview] = useState<BillingOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [showCreateInvoice, setShowCreateInvoice] = useState(false);
  const [showAddPaymentMethod, setShowAddPaymentMethod] = useState(false);

  useEffect(() => {
    loadBillingData();
  }, []);

  const loadBillingData = async () => {
    try {
      setLoading(true);
      const data = await billingApi.getOverview();
      setOverview(data);
    } catch (error) {
      console.error('Error loading billing data:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading && !overview) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
      </div>
    );
  }
  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Billing</h1>
          <p className="text-gray-600">
            Manage invoices, payments, and billing configuration.
          </p>
        </div>
        <button 
          onClick={() => setShowCreateInvoice(true)}
          className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors"
        >
          Create Invoice
        </button>
      </div>

      {/* Billing Overview */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Outstanding</h3>
          <p className="text-2xl font-bold text-gray-900">
            {overview ? billingApi.formatCurrency(overview.outstanding) : '$0.00'}
          </p>
          <p className="text-xs text-red-600 mt-1">
            {overview ? 
              `${overview.recent_invoices.filter(i => i.status === 'overdue').length} overdue invoices` : 
              '0 overdue invoices'
            }
          </p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">This Month</h3>
          <p className="text-2xl font-bold text-gray-900">
            {overview ? billingApi.formatCurrency(overview.this_month) : '$0.00'}
          </p>
          <p className="text-xs text-green-600 mt-1">
            {overview ? 
              `${overview.recent_invoices.filter(i => i.status === 'sent' || i.status === 'paid').length} invoices sent` : 
              '0 invoices sent'
            }
          </p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Collected</h3>
          <p className="text-2xl font-bold text-gray-900">
            {overview ? billingApi.formatCurrency(overview.collected) : '$0.00'}
          </p>
          <p className="text-xs text-green-600 mt-1">All time</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <h3 className="text-sm font-medium text-gray-500">Success Rate</h3>
          <p className="text-2xl font-bold text-gray-900">
            {overview ? `${overview.success_rate}%` : '0%'}
          </p>
          <p className="text-xs text-gray-500 mt-1">Payment success</p>
        </div>
      </div>

      {/* Payment Methods */}
      <div className="bg-white shadow rounded-lg">
        <div className="px-6 py-4 border-b border-gray-200">
          <div className="flex justify-between items-center">
            <h3 className="text-lg font-medium text-gray-900">Payment Methods</h3>
            <button 
              onClick={() => setShowAddPaymentMethod(true)}
              className="text-blue-600 hover:text-blue-700 text-sm font-medium"
            >
              Add Method
            </button>
          </div>
        </div>
        <div className="p-6">
          {overview && overview.payment_methods.length > 0 ? (
            <div className="space-y-4">
              {overview.payment_methods.map((method) => (
                <div key={method.id} className="flex items-center justify-between p-4 border border-gray-200 rounded-lg">
                  <div className="flex items-center space-x-4">
                    <div className="text-gray-400 text-xl">
                      {method.card_brand ? '💳' : '🏦'}
                    </div>
                    <div>
                      <p className="text-sm font-medium text-gray-900">
                        {billingApi.getPaymentMethodDisplay(method)}
                      </p>
                      <p className="text-xs text-gray-500 capitalize">
                        {method.provider}
                        {method.is_default && <span className="ml-2 bg-blue-100 text-blue-800 px-2 py-1 rounded-full text-xs">Default</span>}
                      </p>
                    </div>
                  </div>
                  <button className="text-gray-400 hover:text-gray-600">
                    ⋯
                  </button>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-center py-8">
              <div className="mx-auto h-12 w-12 text-gray-400">
                💳
              </div>
              <h3 className="mt-2 text-sm font-medium text-gray-900">No payment methods</h3>
              <p className="mt-1 text-sm text-gray-500">
                Configure Stripe or PayPal to start accepting payments.
              </p>
              <div className="mt-6">
                <button 
                  onClick={() => setShowAddPaymentMethod(true)}
                  className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors"
                >
                  Configure Payments
                </button>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Recent Invoices */}
      <div className="bg-white shadow rounded-lg overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-200">
          <div className="flex justify-between items-center">
            <h3 className="text-lg font-medium text-gray-900">Recent Invoices</h3>
            <button className="text-blue-600 hover:text-blue-700 text-sm font-medium">
              View All
            </button>
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Invoice
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Customer
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Amount
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Date
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {overview && overview.recent_invoices.length > 0 ? (
                overview.recent_invoices.map((invoice) => (
                  <tr key={invoice.id} className="hover:bg-gray-50">
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      {invoice.invoice_number}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      Account Customer
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {billingApi.formatCurrency(parseInt(invoice.total_amount), invoice.currency)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                        billingApi.getStatusColor(invoice.status) === 'green' ? 'bg-green-100 text-green-800' :
                        billingApi.getStatusColor(invoice.status) === 'yellow' ? 'bg-yellow-100 text-yellow-800' :
                        billingApi.getStatusColor(invoice.status) === 'red' ? 'bg-red-100 text-red-800' :
                        billingApi.getStatusColor(invoice.status) === 'blue' ? 'bg-blue-100 text-blue-800' :
                        'bg-gray-100 text-gray-800'
                      }`}>
                        {billingApi.getStatusText(invoice.status)}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {new Date(invoice.due_date).toLocaleDateString()}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <button className="text-blue-600 hover:text-blue-700 mr-3">View</button>
                      <button className="text-gray-400 hover:text-gray-600">⋯</button>
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={6} className="px-6 py-12 text-center">
                    <p className="text-gray-500">No invoices found.</p>
                    <p className="text-sm text-gray-400 mt-2">
                      Invoices will appear here once you start billing customers.
                    </p>
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};