import React, { useState, useEffect } from 'react';
import { billingApi, BillingOverview } from '../../services/billingApi';
// TODO: Use Invoice and PaymentMethod types for detailed billing data
import { DateRangePicker } from '../../components/common/DateRangePicker';
import CreateInvoiceModal, { InvoiceFormData } from '../../components/billing/CreateInvoiceModal';

export const BillingPage: React.FC = () => {
  const [overview, setOverview] = useState<BillingOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [showCreateInvoice, setShowCreateInvoice] = useState(false);
  // const [showAddPaymentMethod, setShowAddPaymentMethod] = useState(false); // TODO: Implement payment method management
  const [showDateFilter, setShowDateFilter] = useState(false);
  const [dateRange, setDateRange] = useState({
    startDate: new Date(new Date().getFullYear(), new Date().getMonth() - 3, 1), // 3 months ago
    endDate: new Date()
  });

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

  const handleCreateInvoice = async (invoiceData: InvoiceFormData) => {
    try {
      setLoading(true);
      // In a real implementation, this would call the billing API
      console.log('Creating invoice:', invoiceData);
      
      // Simulate API call
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      setShowCreateInvoice(false);
      await loadBillingData(); // Refresh data
    } catch (error) {
      console.error('Error creating invoice:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading && !overview) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-theme-link"></div>
      </div>
    );
  }
  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">Billing</h1>
          <p className="text-theme-secondary">
            Manage invoices, payments, and billing configuration.
          </p>
        </div>
        <button 
          onClick={() => setShowCreateInvoice(true)}
          className="btn-theme btn-theme-primary"
        >
          Create Invoice
        </button>
      </div>

      {/* Date Filter Section */}
      <div className="card-theme p-4">
        <div className="flex justify-between items-center mb-4">
          <h3 className="text-lg font-medium text-theme-primary">Invoice Filtering</h3>
          <button
            onClick={() => setShowDateFilter(!showDateFilter)}
            className="btn-theme btn-theme-outline text-sm"
          >
            {showDateFilter ? 'Hide Filters' : 'Show Filters'}
          </button>
        </div>
        
        {showDateFilter && (
          <DateRangePicker
            startDate={dateRange.startDate}
            endDate={dateRange.endDate}
            onStartDateChange={(startDate) => 
              startDate && setDateRange(prev => ({ ...prev, startDate }))
            }
            onEndDateChange={(endDate) => 
              endDate && setDateRange(prev => ({ ...prev, endDate }))
            }
            showPresets={true}
            maxDate={new Date()}
            className="invoice-date-filter"
          />
        )}
      </div>

      {/* Billing Overview */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Outstanding</h3>
          <p className="text-2xl font-bold text-theme-primary">
            {overview ? billingApi.formatCurrency(overview.outstanding) : '$0.00'}
          </p>
          <p className="text-xs text-theme-error mt-1">
            {overview ? 
              `${overview.recent_invoices.filter(i => i.status === 'overdue').length} overdue invoices` : 
              '0 overdue invoices'
            }
          </p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">This Month</h3>
          <p className="text-2xl font-bold text-theme-primary">
            {overview ? billingApi.formatCurrency(overview.this_month) : '$0.00'}
          </p>
          <p className="text-xs text-theme-success mt-1">
            {overview ? 
              `${overview.recent_invoices.filter(i => i.status === 'sent' || i.status === 'paid').length} invoices sent` : 
              '0 invoices sent'
            }
          </p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Collected</h3>
          <p className="text-2xl font-bold text-theme-primary">
            {overview ? billingApi.formatCurrency(overview.collected) : '$0.00'}
          </p>
          <p className="text-xs text-theme-success mt-1">All time</p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Success Rate</h3>
          <p className="text-2xl font-bold text-theme-primary">
            {overview ? `${overview.success_rate}%` : '0%'}
          </p>
          <p className="text-xs text-theme-secondary mt-1">Payment success</p>
        </div>
      </div>

      {/* Payment Methods */}
      <div className="card-theme shadow">
        <div className="px-6 py-4 border-b border-theme">
          <div className="flex justify-between items-center">
            <h3 className="text-lg font-medium text-theme-primary">Payment Methods</h3>
            {/* TODO: Implement payment method management
            <button 
              onClick={() => setShowAddPaymentMethod(true)}
              className="text-theme-link hover:text-theme-link-hover text-sm font-medium"
            >
              Add Method
            </button>
            */}
          </div>
        </div>
        <div className="p-6">
          {overview && overview.payment_methods.length > 0 ? (
            <div className="space-y-4">
              {overview.payment_methods.map((method) => (
                <div key={method.id} className="flex items-center justify-between p-4 border border-theme rounded-lg">
                  <div className="flex items-center space-x-4">
                    <div className="text-theme-tertiary text-xl">
                      {method.card_brand ? '💳' : '🏦'}
                    </div>
                    <div>
                      <p className="text-sm font-medium text-theme-primary">
                        {billingApi.getPaymentMethodDisplay(method)}
                      </p>
                      <p className="text-xs text-theme-secondary capitalize">
                        {method.provider}
                        {method.is_default && <span className="ml-2 bg-theme-info text-theme-info px-2 py-1 rounded-full text-xs">Default</span>}
                      </p>
                    </div>
                  </div>
                  <button className="text-theme-tertiary hover:text-theme-secondary">
                    ⋯
                  </button>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-center py-8">
              <div className="mx-auto h-12 w-12 text-theme-tertiary">
                💳
              </div>
              <h3 className="mt-2 text-sm font-medium text-theme-primary">No payment methods</h3>
              <p className="mt-1 text-sm text-theme-secondary">
                Configure Stripe or PayPal to start accepting payments.
              </p>
              <div className="mt-6">
                {/* TODO: Implement payment method management
                <button 
                  onClick={() => setShowAddPaymentMethod(true)}
                  className="btn-theme btn-theme-primary"
                >
                  Configure Payments
                </button>
                */}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Recent Invoices */}
      <div className="card-theme shadow overflow-hidden">
        <div className="px-6 py-4 border-b border-theme">
          <div className="flex justify-between items-center">
            <h3 className="text-lg font-medium text-theme-primary">Recent Invoices</h3>
            <button className="text-theme-link hover:text-theme-link-hover text-sm font-medium">
              View All
            </button>
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-theme">
            <thead className="bg-theme-background-secondary">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Invoice
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Customer
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Amount
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Date
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="card-theme divide-y divide-theme">
              {overview && overview.recent_invoices.length > 0 ? (
                overview.recent_invoices.map((invoice) => (
                  <tr key={invoice.id} className="hover:bg-theme-surface-hover">
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-theme-primary">
                      {invoice.invoice_number}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                      Account Customer
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {billingApi.formatCurrency(parseInt(invoice.total_amount), invoice.currency)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                        billingApi.getStatusColor(invoice.status) === 'green' ? 'bg-theme-success text-theme-success' :
                        billingApi.getStatusColor(invoice.status) === 'yellow' ? 'bg-theme-warning text-theme-warning' :
                        billingApi.getStatusColor(invoice.status) === 'red' ? 'bg-theme-error text-theme-error' :
                        billingApi.getStatusColor(invoice.status) === 'blue' ? 'bg-theme-info text-theme-info' :
                        'bg-theme-background-tertiary text-theme-secondary'
                      }`}>
                        {billingApi.getStatusText(invoice.status)}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                      {new Date(invoice.due_date).toLocaleDateString()}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                      <button className="text-theme-link hover:text-theme-link-hover mr-3">View</button>
                      <button className="text-theme-tertiary hover:text-theme-secondary">⋯</button>
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={6} className="px-6 py-12 text-center">
                    <p className="text-theme-secondary">No invoices found.</p>
                    <p className="text-sm text-theme-tertiary mt-2">
                      Invoices will appear here once you start billing customers.
                    </p>
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Create Invoice Modal */}
      <CreateInvoiceModal
        isOpen={showCreateInvoice}
        onClose={() => setShowCreateInvoice(false)}
        onSubmit={handleCreateInvoice}
        loading={loading}
      />
    </div>
  );
};