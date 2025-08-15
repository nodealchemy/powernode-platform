import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { billingApi, BillingOverview } from '../../services/billingApi';
import { DateRangePicker } from '../../components/common/DateRangePicker';
import CreateInvoiceModal, { InvoiceFormData } from '../../components/billing/CreateInvoiceModal';
import { LoadingSpinner } from '../../components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '../../components/layout/PageContainer';
import { FileText, RefreshCw } from 'lucide-react';

export const BillingPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [overview, setOverview] = useState<BillingOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'overview' | 'invoices' | 'payments' | 'analytics'>('overview');
  const [showCreateInvoice, setShowCreateInvoice] = useState(false);
  const [showDateFilter, setShowDateFilter] = useState(false);
  const [dateRange, setDateRange] = useState({
    startDate: new Date(new Date().getFullYear(), new Date().getMonth() - 3, 1), // 3 months ago
    endDate: new Date()
  });

  const loadBillingData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await billingApi.getOverview();
      setOverview(data);
    } catch (err: any) {
      console.error('Error loading billing data:', err);
      const errorMsg = err?.response?.data?.error || err?.message || 'Failed to load billing data';
      setError(errorMsg);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadBillingData();
  }, [loadBillingData]);

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

  const tabs = [
    { id: 'overview', label: 'Overview', icon: '📊' },
    { id: 'invoices', label: 'Invoices', icon: '📄' },
    { id: 'payments', label: 'Payment Methods', icon: '💳' },
    { id: 'analytics', label: 'Analytics', icon: '📈' }
  ] as const;

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: loadBillingData,
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    },
    {
      id: 'create-invoice',
      label: 'Create Invoice',
      onClick: () => setShowCreateInvoice(true),
      variant: 'primary',
      icon: FileText
    }
  ];

  const getBreadcrumbs = () => {
    const baseBreadcrumbs = [
      { label: 'Dashboard', href: '/dashboard', icon: '🏠' },
      { label: 'Billing', icon: '💳' }
    ];
    
    // Add active tab to breadcrumbs
    const activeTabInfo = tabs.find(tab => tab.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      baseBreadcrumbs.push({
        label: activeTabInfo.label,
        icon: activeTabInfo.icon
      });
    }
    
    return baseBreadcrumbs;
  };

  // Handle tab changes
  const handleTabChange = (tabId: string) => {
    setActiveTab(tabId as 'overview' | 'invoices' | 'payments' | 'analytics');
  };

  const getPageDescription = () => {
    if (loading) return "Loading billing data...";
    if (error) return "Error loading billing data";
    return `Manage invoices, payments, and billing configuration for ${user?.account?.name || 'your account'}`;
  };

  const getPageActions = () => {
    if (error) {
      return [{
        id: 'retry',
        label: 'Try Again',
        onClick: loadBillingData,
        variant: 'primary' as const
      }];
    }
    return pageActions;
  };

  return (
    <PageContainer
      title="Billing"
      description={getPageDescription()}
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      {loading ? (
        <LoadingSpinner size="lg" message="Loading billing data..." />
      ) : error ? (
        <div className="alert-theme alert-theme-error">
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <span className="text-xl">⚠️</span>
            </div>
            <div className="ml-3">
              <h3 className="text-sm font-medium">Error Loading Billing Data</h3>
              <p className="mt-1 text-sm">{error}</p>
            </div>
          </div>
        </div>
      ) : (
        <>
          {/* Navigation Tabs */}
          <div className="border-b border-theme mb-6">
            <div className="flex space-x-8 -mb-px">
              {tabs.map((tab) => (
                <button
                  key={tab.id}
                  onClick={() => handleTabChange(tab.id)}
                  className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm whitespace-nowrap ${
                    activeTab === tab.id
                      ? 'border-theme-link text-theme-link'
                      : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
                  }`}
                >
                  <span>{tab.icon}</span>
                  <span>{tab.label}</span>
                </button>
              ))}
            </div>
          </div>

          {/* Tab Content */}
          <div>
        {activeTab === 'overview' && (
          <div className="space-y-6">
            {/* Billing Overview Stats */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">
                  {overview ? billingApi.formatCurrency(overview.outstanding) : '$0.00'}
                </div>
                <div className="text-sm text-theme-secondary">Outstanding</div>
                <div className="text-xs text-theme-tertiary">
                  {overview ? 
                    `${overview.recent_invoices.filter(i => i.status === 'overdue').length} overdue` : 
                    '0 overdue'
                  }
                </div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">
                  {overview ? billingApi.formatCurrency(overview.this_month) : '$0.00'}
                </div>
                <div className="text-sm text-theme-secondary">This Month</div>
                <div className="text-xs text-theme-tertiary">Invoiced</div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">
                  {overview ? billingApi.formatCurrency(overview.collected) : '$0.00'}
                </div>
                <div className="text-sm text-theme-secondary">Collected</div>
                <div className="text-xs text-theme-tertiary">All time</div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">
                  {overview ? `${overview.success_rate}%` : '0%'}
                </div>
                <div className="text-sm text-theme-secondary">Success Rate</div>
                <div className="text-xs text-theme-tertiary">Payment success</div>
              </div>
            </div>

            {/* Quick Actions */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Quick Actions</h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <button 
                  onClick={() => setShowCreateInvoice(true)}
                  className="border border-theme rounded-lg p-4 text-center hover:bg-theme-surface cursor-pointer transition-colors"
                >
                  <div className="text-2xl mb-2">📄</div>
                  <div className="font-medium text-theme-primary">Create Invoice</div>
                  <div className="text-sm text-theme-secondary">Generate a new invoice for customers</div>
                </button>
                <div className="border border-theme rounded-lg p-4 text-center hover:bg-theme-surface cursor-pointer transition-colors">
                  <div className="text-2xl mb-2">💳</div>
                  <div className="font-medium text-theme-primary">Payment Methods</div>
                  <div className="text-sm text-theme-secondary">Configure Stripe and PayPal</div>
                </div>
                <div className="border border-theme rounded-lg p-4 text-center hover:bg-theme-surface cursor-pointer transition-colors">
                  <div className="text-2xl mb-2">📊</div>
                  <div className="font-medium text-theme-primary">View Reports</div>
                  <div className="text-sm text-theme-secondary">Analyze billing performance</div>
                </div>
              </div>
            </div>

            {/* Recent Activity */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Recent Activity</h3>
              <div className="space-y-3">
                <div className="flex items-center space-x-3 py-2">
                  <div className="w-2 h-2 bg-theme-success rounded-full"></div>
                  <span className="text-theme-primary">Invoice #INV-001 paid</span>
                  <span className="text-sm text-theme-secondary">2 hours ago</span>
                </div>
                <div className="flex items-center space-x-3 py-2">
                  <div className="w-2 h-2 bg-theme-info rounded-full"></div>
                  <span className="text-theme-primary">New payment method added</span>
                  <span className="text-sm text-theme-secondary">1 day ago</span>
                </div>
                <div className="flex items-center space-x-3 py-2">
                  <div className="w-2 h-2 bg-theme-warning rounded-full"></div>
                  <span className="text-theme-primary">Invoice #INV-002 overdue</span>
                  <span className="text-sm text-theme-secondary">3 days ago</span>
                </div>
              </div>
            </div>
          </div>
        )}

        {activeTab === 'invoices' && (
          <div className="space-y-6">
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

            {/* Invoices Table */}
            <div className="card-theme shadow overflow-hidden">
              <div className="px-6 py-4 border-b border-theme">
                <div className="flex justify-between items-center">
                  <h3 className="text-lg font-medium text-theme-primary">All Invoices</h3>
                  <button 
                    onClick={() => setShowCreateInvoice(true)}
                    className="btn-theme btn-theme-primary text-sm"
                  >
                    Create Invoice
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
                          <span className="text-6xl">📄</span>
                          <h3 className="text-lg font-medium text-theme-primary mt-2">No invoices found</h3>
                          <p className="text-theme-secondary">Create your first invoice to get started.</p>
                          <button 
                            onClick={() => setShowCreateInvoice(true)}
                            className="mt-4 btn-theme btn-theme-primary"
                          >
                            Create Invoice
                          </button>
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}

        {activeTab === 'payments' && (
          <div className="space-y-6">
            {/* Payment Methods */}
            <div className="card-theme shadow">
              <div className="px-6 py-4 border-b border-theme">
                <div className="flex justify-between items-center">
                  <h3 className="text-lg font-medium text-theme-primary">Payment Methods</h3>
                  <button className="btn-theme btn-theme-primary text-sm">
                    Add Payment Method
                  </button>
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
                    <div className="mx-auto h-12 w-12 text-theme-tertiary text-6xl">
                      💳
                    </div>
                    <h3 className="mt-2 text-sm font-medium text-theme-primary">No payment methods</h3>
                    <p className="mt-1 text-sm text-theme-secondary">
                      Configure Stripe or PayPal to start accepting payments.
                    </p>
                    <div className="mt-6">
                      <button className="btn-theme btn-theme-primary">
                        Configure Payments
                      </button>
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* Payment Gateway Status */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Gateway Status</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="border border-theme rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center space-x-3">
                      <span className="text-2xl">🌟</span>
                      <div>
                        <h4 className="font-medium text-theme-primary">Stripe</h4>
                        <p className="text-sm text-theme-secondary">Payment processing</p>
                      </div>
                    </div>
                    <span className="px-2 py-1 text-xs rounded bg-theme-success text-theme-success">Connected</span>
                  </div>
                </div>
                <div className="border border-theme rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center space-x-3">
                      <span className="text-2xl">🏛️</span>
                      <div>
                        <h4 className="font-medium text-theme-primary">PayPal</h4>
                        <p className="text-sm text-theme-secondary">Alternative payments</p>
                      </div>
                    </div>
                    <span className="px-2 py-1 text-xs rounded bg-theme-warning text-theme-warning">Setup Required</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {activeTab === 'analytics' && (
          <div className="space-y-6">
            {/* Revenue Analytics */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">
                  {overview ? overview.recent_invoices.length : 0}
                </div>
                <div className="text-sm text-theme-secondary">Total Invoices</div>
                <div className="text-xs text-theme-tertiary">All time</div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">
                  {overview ? overview.recent_invoices.filter(i => i.status === 'paid').length : 0}
                </div>
                <div className="text-sm text-theme-secondary">Paid Invoices</div>
                <div className="text-xs text-theme-tertiary">Success rate</div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">
                  {overview ? overview.payment_methods.length : 0}
                </div>
                <div className="text-sm text-theme-secondary">Payment Methods</div>
                <div className="text-xs text-theme-tertiary">Active</div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">
                  {overview ? `${overview.success_rate}%` : '0%'}
                </div>
                <div className="text-sm text-theme-secondary">Success Rate</div>
                <div className="text-xs text-theme-tertiary">Payment success</div>
              </div>
            </div>
            
            {/* Payment Trends */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Payment Trends</h3>
              <div className="space-y-3">
                <div className="flex items-center justify-between py-2">
                  <div className="flex items-center space-x-3">
                    <span className="text-theme-secondary font-medium">1</span>
                    <span className="text-lg">💳</span>
                    <span className="text-theme-primary">Credit Card</span>
                  </div>
                  <div className="text-sm text-theme-secondary">85% of payments</div>
                </div>
                <div className="flex items-center justify-between py-2">
                  <div className="flex items-center space-x-3">
                    <span className="text-theme-secondary font-medium">2</span>
                    <span className="text-lg">🏛️</span>
                    <span className="text-theme-primary">Bank Transfer</span>
                  </div>
                  <div className="text-sm text-theme-secondary">10% of payments</div>
                </div>
                <div className="flex items-center justify-between py-2">
                  <div className="flex items-center space-x-3">
                    <span className="text-theme-secondary font-medium">3</span>
                    <span className="text-lg">📱</span>
                    <span className="text-theme-primary">Digital Wallet</span>
                  </div>
                  <div className="text-sm text-theme-secondary">5% of payments</div>
                </div>
              </div>
            </div>

            {/* Invoice Status Breakdown */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Invoice Status Breakdown</h3>
              <div className="space-y-4">
                {overview && overview.recent_invoices.length > 0 ? (
                  ['paid', 'sent', 'draft', 'overdue'].map((status) => {
                    const count = overview.recent_invoices.filter(i => i.status === status).length;
                    const percentage = ((count / overview.recent_invoices.length) * 100).toFixed(1);
                    return (
                      <div key={status} className="flex items-center justify-between py-2">
                        <div className="flex items-center space-x-3">
                          <span className={`w-3 h-3 rounded-full ${
                            status === 'paid' ? 'bg-theme-success' :
                            status === 'sent' ? 'bg-theme-info' :
                            status === 'draft' ? 'bg-theme-secondary' :
                            'bg-theme-error'
                          }`}></span>
                          <span className="text-theme-primary capitalize">{status}</span>
                        </div>
                        <div className="text-sm text-theme-secondary">
                          {count} invoices ({percentage}%)
                        </div>
                      </div>
                    );
                  })
                ) : (
                  <p className="text-theme-secondary text-center py-4">No invoice data available</p>
                )}
              </div>
            </div>
          </div>
        )}
      </div>

          </>
        )}
      
      {/* Create Invoice Modal */}
      <CreateInvoiceModal
        isOpen={showCreateInvoice}
        onClose={() => setShowCreateInvoice(false)}
        onSubmit={handleCreateInvoice}
        loading={loading}
      />
    </PageContainer>
  );
};