import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { useLocation } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { billingApi, BillingOverview } from '@/features/billing/services/billingApi';
import { DateRangePicker } from '@/shared/components/ui/DateRangePicker';
import CreateInvoiceModal, { InvoiceFormData } from '@/features/billing/components/CreateInvoiceModal';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { FileText, RefreshCw } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { MetricCard, ActionCard } from '@/shared/components/ui/Card';

export const BillingPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const location = useLocation();
  const [overview, setOverview] = useState<BillingOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
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
    { id: 'overview', label: 'Overview', icon: '📊', path: '/' },
    { id: 'invoices', label: 'Invoices', icon: '📄', path: '/invoices' },
    { id: 'analytics', label: 'Analytics', icon: '📈', path: '/analytics' }
  ];

  // Get active tab from URL
  const getActiveTab = () => {
    const path = location.pathname;
    if (path === '/app/business/billing') return 'overview';
    if (path.includes('/invoices')) return 'invoices';
    if (path.includes('/analytics')) return 'analytics';
    return 'overview';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

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
      { label: 'Dashboard', href: '/app', icon: '🏠' },
      { label: 'Business', href: '/app/business', icon: '💼' },
      { label: 'Billing', icon: '💳' }
    ];
    
    // Add active tab to breadcrumbs if not the default overview tab
    const activeTabInfo = tabs.find(tab => tab.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      baseBreadcrumbs.push({
        label: activeTabInfo.label,
        icon: activeTabInfo.icon
      });
    }
    
    return baseBreadcrumbs;
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
          <TabContainer
            tabs={tabs}
            activeTab={activeTab}
            onTabChange={setActiveTab}
            basePath="/app/business/billing"
            variant="underline"
            className="mb-6"
          >
            <TabPanel tabId="overview" activeTab={activeTab}>
              <div className="space-y-6">
            {/* Billing Overview Stats */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
              <MetricCard
                title="Outstanding"
                value={overview ? billingApi.formatCurrency(overview.outstanding) : '$0.00'}
                icon="💳"
                description={overview ? 
                  `${overview.recent_invoices.filter(i => i.status === 'overdue').length} overdue` : 
                  '0 overdue'
                }
              />
              <MetricCard
                title="This Month"
                value={overview ? billingApi.formatCurrency(overview.this_month) : '$0.00'}
                icon="📊"
                description="Invoiced"
              />
              <MetricCard
                title="Collected"
                value={overview ? billingApi.formatCurrency(overview.collected) : '$0.00'}
                icon="💰"
                description="All time"
              />
              <MetricCard
                title="Success Rate"
                value={overview ? `${overview.success_rate}%` : '0%'}
                icon="✅"
                description="Payment success"
              />
            </div>

            {/* Quick Actions */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <ActionCard
                title="Create Invoice"
                description="Generate a new invoice for customers"
                icon="📄"
                onClick={() => setShowCreateInvoice(true)}
              />
              <ActionCard
                title="View Reports"
                description="Analyze billing performance"
                icon="📊"
                onClick={() => setActiveTab('analytics')}
              />
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
                  <div className="w-2 h-2 bg-theme-warning rounded-full"></div>
                  <span className="text-theme-primary">Invoice #INV-002 overdue</span>
                  <span className="text-sm text-theme-secondary">3 days ago</span>
                </div>
              </div>
            </div>
              </div>
            </TabPanel>

            <TabPanel tabId="invoices" activeTab={activeTab}>
              <div className="space-y-6">
            {/* Date Filter Section */}
            <div className="card-theme p-4">
              <div className="flex justify-between items-center mb-4">
                <h3 className="text-lg font-medium text-theme-primary">Invoice Filtering</h3>
                <Button
                  onClick={() => setShowDateFilter(!showDateFilter)}
                  variant="secondary"
                  size="sm"
                >
                  {showDateFilter ? 'Hide Filters' : 'Show Filters'}
                </Button>
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
                  <Button 
                    onClick={() => setShowCreateInvoice(true)}
                    variant="primary"
                    size="sm"
                  >
                    Create Invoice
                  </Button>
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
                            <Button variant="ghost" size="xs" className="text-theme-link hover:text-theme-link-hover mr-1">View</Button>
                            <Button variant="ghost" size="xs" iconOnly className="text-theme-tertiary hover:text-theme-secondary">⋯</Button>
                          </td>
                        </tr>
                      ))
                    ) : (
                      <tr>
                        <td colSpan={6} className="px-6 py-12 text-center">
                          <span className="text-6xl">📄</span>
                          <h3 className="text-lg font-medium text-theme-primary mt-2">No invoices found</h3>
                          <p className="text-theme-secondary">Create your first invoice to get started.</p>
                          <Button 
                            onClick={() => setShowCreateInvoice(true)}
                            variant="primary"
                            className="mt-4"
                          >
                            Create Invoice
                          </Button>
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
              </div>
            </TabPanel>

            <TabPanel tabId="analytics" activeTab={activeTab}>
              <div className="space-y-6">
            {/* Revenue Analytics */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              <MetricCard
                title="Total Invoices"
                value={overview ? overview.recent_invoices.length : 0}
                icon="📄"
                description="All time"
              />
              <MetricCard
                title="Paid Invoices"
                value={overview ? overview.recent_invoices.filter(i => i.status === 'paid').length : 0}
                icon="✅"
                description="Success rate"
              />
              <MetricCard
                title="Success Rate"
                value={overview ? `${overview.success_rate}%` : '0%'}
                icon="📊"
                description="Payment success"
              />
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
            </TabPanel>
          </TabContainer>

          </>
        )}
      
      {/* Create Invoice Modal */}
      <CreateInvoiceModal
        isOpen={showCreateInvoice}
        onClose={() => setShowCreateInvoice(false)}
        onSubmit={handleCreateInvoice}
      />
    </PageContainer>
  );
};