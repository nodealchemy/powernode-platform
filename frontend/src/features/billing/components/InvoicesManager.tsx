import React, { useState, useEffect, useCallback } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { 
  FileText, Download, Send, DollarSign, AlertTriangle, 
  Check, Clock, X, Filter, Search
} from 'lucide-react';
import { invoicesApi, Invoice, InvoiceFilters, InvoiceStats } from '@/shared/services/invoicesApi';
import { useNotification } from '@/shared/hooks/useNotification';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface InvoicesManagerProps {
  customerId?: string;
  subscriptionId?: string;
  showFilters?: boolean;
  showStats?: boolean;
}

export const InvoicesManager: React.FC<InvoicesManagerProps> = ({
InvoicesManager.displayName = 'InvoicesManager';
  customerId,
  subscriptionId,
  showFilters = true,
  showStats = true
}) => {
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [stats, setStats] = useState<InvoiceStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<{ [key: string]: boolean }>({});
  const [currentPage, setCurrentPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [searchTerm, setSearchTerm] = useState('');
  const [filters, setFilters] = useState<InvoiceFilters>({
    customer_id: customerId,
    subscription_id: subscriptionId
  });
  const [showFiltersPanel, setShowFiltersPanel] = useState(false);
  
  const { showNotification } = useNotification();
  const perPage = 20;

  const loadInvoices = useCallback(async () => {
    try {
      setLoading(true);
      const response = await invoicesApi.getInvoices(currentPage, perPage, filters);
      
      if (response.success) {
        setInvoices(response.invoices);
        setTotalPages(response.pagination.total_pages);
      } else {
        showNotification('Failed to load invoices', 'error');
      }
    } catch (error: any) {
      showNotification('Failed to load invoices', 'error');
    } finally {
      setLoading(false);
    }
  }, [currentPage, perPage, filters, showNotification]);

  const loadStats = async () => {
    try {
      const statsData = await invoicesApi.getInvoiceStats();
      setStats(statsData);
    } catch (error: any) {
      console.error('Failed to load invoice stats:', error);
    }
  };

  useEffect(() => {
    loadInvoices();
    if (showStats) {
      loadStats();
    }
  }, [currentPage, filters, loadInvoices, showStats]);

  const handleAction = async (action: string, invoiceId: string, data?: any) => {
    try {
      setActionLoading(prev => ({ ...prev, [invoiceId]: true }));
      let response;
      
      switch (action) {
        case 'send':
          response = await invoicesApi.sendInvoice(invoiceId);
          break;
        case 'void':
          response = await invoicesApi.voidInvoice(invoiceId, data?.reason);
          break;
        case 'retry':
          response = await invoicesApi.retryPayment(invoiceId);
          break;
        case 'mark_paid':
          response = await invoicesApi.markAsPaid(invoiceId, data);
          break;
        default:
          throw new Error('Unknown action');
      }
      
      if (response.success) {
        showNotification(response.message || 'Action completed successfully', 'success');
        await loadInvoices();
        if (showStats) {
          await loadStats();
        }
      } else {
        showNotification(response.error || 'Action failed', 'error');
      }
    } catch (error: any) {
      showNotification('Action failed', 'error');
    } finally {
      setActionLoading(prev => ({ ...prev, [invoiceId]: false }));
    }
  };

  const handleDownloadPDF = async (invoiceId: string) => {
    try {
      setActionLoading(prev => ({ ...prev, [invoiceId]: true }));
      const blob = await invoicesApi.downloadPDF(invoiceId);
      
      // Create download link
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `invoice-${invoiceId}.pdf`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      window.URL.revokeObjectURL(url);
      
      showNotification('Invoice PDF downloaded', 'success');
    } catch (error: any) {
      showNotification('Failed to download invoice PDF', 'error');
    } finally {
      setActionLoading(prev => ({ ...prev, [invoiceId]: false }));
    }
  };

  const getStatusColor = (status: string): string => {
    const colorMap = {
      green: 'bg-theme-success-background text-theme-success border-theme-success',
      yellow: 'bg-theme-warning-background text-theme-warning border-theme-warning',
      red: 'bg-theme-error-background text-theme-error border-theme-error',
      blue: 'bg-theme-info-background text-theme-info border-theme-info',
      gray: 'bg-theme-surface text-theme-secondary border-theme'
    };
    return colorMap[invoicesApi.getStatusColor(status)] || colorMap.gray;
  };

  const filteredInvoices = invoices.filter(invoice =>
    searchTerm === '' || 
    invoice.invoice_number.toLowerCase().includes(searchTerm.toLowerCase()) ||
    invoice.customer.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    invoice.customer.email.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="space-y-6">
      {/* Stats Cards */}
      {showStats && stats && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Total Invoices</p>
                <p className="text-2xl font-semibold text-theme-primary">{stats.total_invoices}</p>
              </div>
              <FileText className="w-8 h-8 text-theme-secondary" />
            </div>
          </div>
          
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Outstanding</p>
                <p className="text-2xl font-semibold text-theme-primary">
                  {invoicesApi.formatAmount(stats.outstanding_amount)}
                </p>
              </div>
              <Clock className="w-8 h-8 text-theme-warning" />
            </div>
          </div>
          
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Overdue</p>
                <p className="text-2xl font-semibold text-theme-error">
                  {invoicesApi.formatAmount(stats.overdue_amount)}
                </p>
              </div>
              <AlertTriangle className="w-8 h-8 text-theme-error" />
            </div>
          </div>
          
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Success Rate</p>
                <p className="text-2xl font-semibold text-theme-success">
                  {stats.payment_success_rate.toFixed(1)}%
                </p>
              </div>
              <Check className="w-8 h-8 text-theme-success" />
            </div>
          </div>
        </div>
      )}

      {/* Header and Controls */}
      <div className="flex flex-col sm:flex-row gap-4 justify-between">
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Invoices</h3>
          <p className="text-sm text-theme-secondary">
            Manage customer invoices and payments
          </p>
        </div>
        
        <div className="flex items-center gap-2">
          {/* Search */}
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-theme-secondary" />
            <input
              type="text"
              placeholder="Search invoices..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10 pr-4 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
            />
          </div>
          
          {/* Filters */}
          {showFilters && (
            <Button variant="outline" onClick={() => setShowFiltersPanel(!showFiltersPanel)}
              className="px-3 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface transition-colors flex items-center gap-2"
            >
              <Filter className="w-4 h-4" />
              Filters
            </Button>
          )}
        </div>
      </div>

      {/* Filters Panel */}
      {showFiltersPanel && (
        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Status
              </label>
              <select
                value={filters.status?.[0] || ''}
                onChange={(e) => setFilters(prev => ({
                  ...prev,
                  status: e.target.value ? [e.target.value] : undefined
                }))}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              >
                <option value="">All Statuses</option>
                <option value="draft">Draft</option>
                <option value="open">Open</option>
                <option value="paid">Paid</option>
                <option value="overdue">Overdue</option>
                <option value="void">Void</option>
              </select>
            </div>
            
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Date Range
              </label>
              <div className="flex gap-2">
                <input
                  type="date"
                  value={filters.date_range?.start_date || ''}
                  onChange={(e) => setFilters(prev => ({
                    ...prev,
                    date_range: {
                      ...prev.date_range,
                      start_date: e.target.value,
                      end_date: prev.date_range?.end_date || ''
                    }
                  }))}
                  className="flex-1 px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                />
                <input
                  type="date"
                  value={filters.date_range?.end_date || ''}
                  onChange={(e) => setFilters(prev => ({
                    ...prev,
                    date_range: {
                      ...prev.date_range,
                      start_date: prev.date_range?.start_date || '',
                      end_date: e.target.value
                    }
                  }))}
                  className="flex-1 px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                />
              </div>
            </div>
            
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Sort By
              </label>
              <select
                value={filters.sort_by || 'created_at'}
                onChange={(e) => setFilters(prev => ({
                  ...prev,
                  sort_by: e.target.value as any
                }))}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              >
                <option value="created_at">Created Date</option>
                <option value="due_date">Due Date</option>
                <option value="amount_due">Amount</option>
                <option value="status">Status</option>
              </select>
            </div>
          </div>
        </div>
      )}

      {/* Invoices Table */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <LoadingSpinner size="lg" />
          </div>
        ) : filteredInvoices.length === 0 ? (
          <div className="text-center py-12">
            <FileText className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
            <h4 className="text-lg font-medium text-theme-primary mb-2">No Invoices Found</h4>
            <p className="text-theme-secondary">
              {searchTerm ? 'No invoices match your search criteria.' : 'No invoices have been created yet.'}
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-theme-background">
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
                    Due Date
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {filteredInvoices.map((invoice) => (
                  <tr key={invoice.id} className="hover:bg-theme-background transition-colors">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div>
                        <div className="text-sm font-medium text-theme-primary">
                          {invoice.invoice_number}
                        </div>
                        <div className="text-sm text-theme-secondary">
                          {new Date(invoice.issue_date).toLocaleDateString()}
                        </div>
                      </div>
                    </td>
                    
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div>
                        <div className="text-sm font-medium text-theme-primary">
                          {invoice.customer.name}
                        </div>
                        <div className="text-sm text-theme-secondary">
                          {invoice.customer.email}
                        </div>
                      </div>
                    </td>
                    
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm font-medium text-theme-primary">
                        {invoicesApi.formatAmount(invoice.total, invoice.currency)}
                      </div>
                      {invoice.amount_remaining > 0 && (
                        <div className="text-sm text-theme-secondary">
                          {invoicesApi.formatAmount(invoice.amount_remaining, invoice.currency)} remaining
                        </div>
                      )}
                    </td>
                    
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full border ${getStatusColor(invoice.status)}`}>
                        {invoicesApi.getStatusText(invoice.status)}
                      </span>
                      {invoicesApi.isOverdue(invoice) && (
                        <div className="text-xs text-theme-error mt-1">
                          {invoicesApi.getDaysOverdue(invoice)} days overdue
                        </div>
                      )}
                    </td>
                    
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {new Date(invoice.due_date).toLocaleDateString()}
                    </td>
                    
                    <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      <div className="flex items-center justify-end gap-2">
                        <Button variant="outline" onClick={() => handleDownloadPDF(invoice.id)}
                          disabled={actionLoading[invoice.id]}
                          className="p-2 text-theme-secondary hover:text-theme-primary transition-colors disabled:opacity-50"
                          title="Download PDF"
                        >
                          {actionLoading[invoice.id] ? (
                            <LoadingSpinner size="sm" />
                          ) : (
                            <Download className="w-4 h-4" />
                          )}
                        </Button>
                        
                        {invoice.status === 'draft' && (
                          <Button variant="outline" onClick={() => handleAction('send', invoice.id)}
                            disabled={actionLoading[invoice.id]}
                            className="p-2 text-theme-secondary hover:text-theme-primary transition-colors disabled:opacity-50"
                            title="Send Invoice"
                          >
                            <Send className="w-4 h-4" />
                          </Button>
                        )}
                        
                        {(invoice.status === 'open' || invoice.status === 'overdue') && (
                          <>
                            <Button variant="outline" onClick={() => handleAction('retry', invoice.id)}
                              disabled={actionLoading[invoice.id]}
                              className="p-2 text-theme-secondary hover:text-theme-primary transition-colors disabled:opacity-50"
                              title="Retry Payment"
                            >
                              <DollarSign className="w-4 h-4" />
                            </Button>
                            
                            <Button variant="outline" onClick={() => {
                                const paymentData = {
                                  amount: invoice.amount_remaining,
                                  payment_method: 'manual',
                                  notes: 'Manually marked as paid'
                                };
                                handleAction('mark_paid', invoice.id, paymentData);
                              }}
                              disabled={actionLoading[invoice.id]}
                              className="p-2 text-theme-success hover:text-theme-success-hover transition-colors disabled:opacity-50"
                              title="Mark as Paid"
                            >
                              <Check className="w-4 h-4" />
                            </Button>
                          </>
                        )}
                        
                        {(invoice.status === 'draft' || invoice.status === 'open') && (
                          <Button variant="outline" onClick={() => handleAction('void', invoice.id, { reason: 'Manual void' })}
                            disabled={actionLoading[invoice.id]}
                            className="p-2 text-theme-error hover:text-theme-error-hover transition-colors disabled:opacity-50"
                            title="Void Invoice"
                          >
                            <X className="w-4 h-4" />
                          </Button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between">
          <div className="text-sm text-theme-secondary">
            Page {currentPage} of {totalPages}
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => setCurrentPage(prev => Math.max(1, prev - 1))}
              disabled={currentPage === 1}
              className="px-3 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Previous
            </Button>
            <Button variant="outline" onClick={() => setCurrentPage(prev => Math.min(totalPages, prev + 1))}
              disabled={currentPage === totalPages}
              className="px-3 py-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Next
            </Button>
          </div>
        </div>
      )}
    </div>
  );
};

export default InvoicesManager;