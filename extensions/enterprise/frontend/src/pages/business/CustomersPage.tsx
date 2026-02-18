import React, { useState, useEffect, useCallback } from 'react';
import { useCustomerWebSocket } from '@/shared/hooks/useCustomerWebSocket';
import { customersApi, CreateCustomerRequest } from '@/shared/services/business/customersApi';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Users, RefreshCw } from 'lucide-react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { formatCurrency, formatDate } from '@/shared/utils/formatters';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { getCustomerStatusColor, getCustomerStatusText, getSubscriptionStatusColor, getSubscriptionStatusText } from '@/shared/utils/statusHelpers';

interface Customer {
  id: string;
  name: string;
  status: string;
  subdomain?: string;
  created_at: string;
  mrr: number;
  user?: {
    first_name?: string;
    email: string;
  };
  subscription?: {
    status: string;
    plan: {
      name: string;
      price_cents: number;
    };
  };
}

interface CustomerStats {
  total_customers: number;
  active_customers: number;
  active_subscriptions: number;
  new_this_month: number;
  total_mrr: number;
  churn_rate: number;
}

export const CustomersPage: React.FC = () => {
  const { addNotification } = useNotifications();
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [stats, setStats] = useState<CustomerStats | null>(null);
  const [searchResults, setSearchResults] = useState<Customer[]>([]);
  const [showAddModal, setShowAddModal] = useState(false);
  const [addingCustomer, setAddingCustomer] = useState(false);

  // Type guards for WebSocket data
  const isCustomerUpdateData = (data: unknown): data is { customer?: Customer; stats?: CustomerStats } => {
    return typeof data === 'object' && data !== null;
  };

  const isSearchResultData = (data: unknown): data is { results?: Customer[] } => {
    return typeof data === 'object' && data !== null && 'results' in data;
  };

  const {
    searchCustomers,
    updateCustomerStatus,
    loadCustomers
  } = useCustomerWebSocket({
    onCustomerUpdate: (data) => {
      if (!isCustomerUpdateData(data)) return;
      
      // Handle customer updates
      if (data.customer) {
        const updatedCustomer = data.customer;
        setCustomers(prev => prev.map(c =>
          c.id === updatedCustomer.id ? { ...c, ...updatedCustomer } : c
        ));
      }
      if (data.stats) {
        setStats(data.stats);
      }
    },
    onSearchResults: (data) => {
      if (!isSearchResultData(data)) return;

      if (data.results) {
        setSearchResults(data.results);
        setShowSearchResults(true);
      }
    },
    onError: (errorMessage) => {
      addNotification({
        type: 'error',
        title: 'Connection Error',
        message: errorMessage
      });
    }
  });

  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [planFilter, setPlanFilter] = useState('all');
  const [loading, setLoading] = useState(true);
  const [showSearchResults, setShowSearchResults] = useState(false);

  // Load initial customer data
  useEffect(() => {
    const loadInitialData = async () => {
      try {
        setLoading(true);
        await loadCustomers({ page: 1, per_page: 50 });
      } catch (_error) {
        // Error handling could be added here
      } finally {
        setLoading(false);
      }
    };

    loadInitialData();
  }, [loadCustomers]);

  // Handle search with debouncing
  const handleSearch = useCallback(async (query: string) => {
    setSearchQuery(query);
    setShowSearchResults(query.length > 0);
    
    if (query.length > 2) {
      await searchCustomers(query, {
        status: statusFilter !== 'all' ? statusFilter : undefined,
        plan: planFilter !== 'all' ? planFilter : undefined
      });
    } else if (query.length === 0) {
      setShowSearchResults(false);
      await loadCustomers({
        status: statusFilter !== 'all' ? statusFilter : undefined,
        plan: planFilter !== 'all' ? planFilter : undefined
      });
    }
  }, [searchCustomers, loadCustomers, statusFilter, planFilter]);

  const handleStatusChange = async (customer_id: string, newStatus: string) => {
    await updateCustomerStatus(customer_id, newStatus);
  };

  const handleFilterChange = useCallback(async () => {
    if (searchQuery.length > 2) {
      await searchCustomers(searchQuery, {
        status: statusFilter !== 'all' ? statusFilter : undefined,
        plan: planFilter !== 'all' ? planFilter : undefined
      });
    } else {
      await loadCustomers({
        status: statusFilter !== 'all' ? statusFilter : undefined,
        plan: planFilter !== 'all' ? planFilter : undefined
      });
    }
  }, [searchQuery, statusFilter, planFilter, searchCustomers, loadCustomers]);

  useEffect(() => {
    handleFilterChange();
  }, [statusFilter, planFilter, handleFilterChange]);

  const displayCustomers = showSearchResults ? searchResults : customers;

  const formatNumber = (num: number) => {
    return new Intl.NumberFormat().format(num);
  };

  const getStatusBadge = (status: string) => {
    const colors = getCustomerStatusColor(status);
    const colorClasses = {
      green: 'bg-theme-success text-theme-success',
      yellow: 'bg-theme-warning text-theme-warning',
      red: 'bg-theme-error text-theme-error',
      gray: 'bg-theme-background-tertiary text-theme-secondary'
    };

    const colorClass = colors === 'green' ? colorClasses.green :
                      colors === 'yellow' ? colorClasses.yellow :
                      colors === 'red' ? colorClasses.red :
                      colorClasses.gray;

    return (
      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${colorClass}`}>
        {getCustomerStatusText(status)}
      </span>
    );
  };

  const getSubscriptionBadge = (status: string) => {
    const colors = getSubscriptionStatusColor(status);
    const colorClasses = {
      green: 'bg-theme-success text-theme-success',
      blue: 'bg-theme-info text-theme-info',
      yellow: 'bg-theme-warning text-theme-warning',
      red: 'bg-theme-error text-theme-error',
      gray: 'bg-theme-background-tertiary text-theme-secondary'
    };

    const colorClass = colors === 'green' ? colorClasses.green :
                      colors === 'blue' ? colorClasses.blue :
                      colors === 'yellow' ? colorClasses.yellow :
                      colors === 'red' ? colorClasses.red :
                      colorClasses.gray;

    return (
      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${colorClass}`}>
        {getSubscriptionStatusText(status)}
      </span>
    );
  };

  const handleAddCustomer = async (formData: CreateCustomerRequest) => {
    setAddingCustomer(true);
    try {
      const response = await customersApi.createCustomer(formData);
      if (response.success && response.customer) {
        addNotification({
          type: 'success',
          title: 'Customer Created',
          message: `Successfully created customer "${response.customer.name}"`
        });
        setShowAddModal(false);
        // Reload customers
        await loadCustomers({ page: 1, per_page: 50 });
      } else {
        addNotification({
          type: 'error',
          title: 'Creation Failed',
          message: response.errors?.join(', ') || 'Failed to create customer'
        });
      }
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Error',
        message: error instanceof Error ? error.message : 'Failed to create customer'
      });
    } finally {
      setAddingCustomer(false);
    }
  };

  // Manual refresh handler
  const handleRefresh = useCallback(async () => {
    setLoading(true);
    try {
      await loadCustomers({
        page: 1,
        per_page: 50,
        status: statusFilter !== 'all' ? statusFilter : undefined,
        plan: planFilter !== 'all' ? planFilter : undefined
      });
      addNotification({
        type: 'success',
        title: 'Refreshed',
        message: 'Customer data refreshed'
      });
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Refresh Failed',
        message: 'Failed to refresh customer data'
      });
    } finally {
      setLoading(false);
    }
  }, [loadCustomers, statusFilter, planFilter, addNotification]);

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: handleRefresh,
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    },
    {
      id: 'add-customer',
      label: 'Add Customer',
      onClick: () => setShowAddModal(true),
      variant: 'primary',
      icon: Users
    }
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Business', href: '/app/business' },
    { label: 'Customers' }
  ];

  return (
    <PageContainer
      title="Customers"
      description="Manage your customer accounts and their subscriptions."
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      <div className="space-y-6">
        {/* Customer Stats */}
        <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-6">
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Total Customers</h3>
          <p className="text-2xl font-bold text-theme-primary">{formatNumber(stats?.total_customers || 0)}</p>
          <p className="text-xs text-theme-secondary mt-1">All time</p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Active Customers</h3>
          <p className="text-2xl font-bold text-theme-primary">{formatNumber(stats?.active_customers || 0)}</p>
          <p className="text-xs text-theme-success mt-1">Currently active</p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Active Subscriptions</h3>
          <p className="text-2xl font-bold text-theme-primary">{formatNumber(stats?.active_subscriptions || 0)}</p>
          <p className="text-xs text-theme-success mt-1">Paying customers</p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">New This Month</h3>
          <p className="text-2xl font-bold text-theme-primary">{formatNumber(stats?.new_this_month || 0)}</p>
          <p className="text-xs text-theme-info mt-1">New customers</p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Total MRR</h3>
          <p className="text-2xl font-bold text-theme-primary">{formatCurrency(stats?.total_mrr || 0)}</p>
          <p className="text-xs text-theme-success mt-1">Monthly recurring</p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Churn Rate</h3>
          <p className="text-2xl font-bold text-theme-primary">{(stats?.churn_rate || 0).toFixed(1)}%</p>
          <p className="text-xs text-theme-secondary mt-1">This month</p>
        </div>
      </div>

      {/* Search and Filters */}
      <div className="card-theme p-6">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div className="flex-1 max-w-lg">
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => handleSearch(e.target.value)}
              placeholder="Search customers by name or email..."
              className="input-theme w-full"
            />
          </div>
          <div className="flex gap-2">
            <select 
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="select-theme"
            >
              <option value="all">All Status</option>
              <option value="active">Active</option>
              <option value="suspended">Suspended</option>
              <option value="cancelled">Cancelled</option>
            </select>
            <select 
              value={planFilter}
              onChange={(e) => setPlanFilter(e.target.value)}
              className="select-theme"
            >
              <option value="all">All Plans</option>
              <option value="starter">Starter</option>
              <option value="professional">Professional</option>
              <option value="enterprise">Enterprise</option>
            </select>
          </div>
        </div>
      </div>

      {/* Customer Table */}
      <div className="card-theme shadow overflow-hidden">
        <div className="px-6 py-4 border-b border-theme">
          <div className="flex justify-between items-center">
            <h3 className="text-lg font-medium text-theme-primary">Customer List</h3>
            {showSearchResults && (
              <span className="text-sm text-theme-secondary">
                {searchResults.length} search results
              </span>
            )}
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-theme">
            <thead className="bg-theme-background-secondary">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Customer
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Plan
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Joined
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  MRR
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="card-theme divide-y divide-theme">
              {loading ? (
                <tr>
                  <td colSpan={6} className="px-6 py-12">
                    <LoadingSpinner message="Loading customers..." />
                  </td>
                </tr>
              ) : displayCustomers.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-6 py-12 text-center">
                    <p className="text-theme-secondary">
                      {showSearchResults ? 'No customers found matching your search.' : 'No customers found.'}
                    </p>
                    <p className="text-sm text-theme-tertiary mt-2">
                      {showSearchResults 
                        ? 'Try adjusting your search terms or filters.'
                        : 'Customer data will appear here once you have registered customers.'
                      }
                    </p>
                  </td>
                </tr>
              ) : (
                displayCustomers.map((customer) => (
                  <tr key={customer.id} className="hover:bg-theme-surface-hover">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center">
                        <div className="h-10 w-10 flex-shrink-0">
                          <div className="h-10 w-10 rounded-full bg-theme-info flex items-center justify-center">
                            <span className="text-theme-info font-medium">
                              {customer.user?.first_name?.[0] || customer.name[0]}
                            </span>
                          </div>
                        </div>
                        <div className="ml-4">
                          <div className="text-sm font-medium text-theme-primary">{customer.name}</div>
                          <div className="text-sm text-theme-secondary">
                            {customer.user?.email || 'No primary user'}
                          </div>
                          {customer.subdomain && (
                            <div className="text-xs text-theme-tertiary">{customer.subdomain}</div>
                          )}
                        </div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      {customer.subscription ? (
                        <div>
                          <div className="text-sm font-medium text-theme-primary">
                            {customer.subscription.plan.name}
                          </div>
                          <div className="text-sm text-theme-secondary">
                            {formatCurrency(customer.subscription.plan.price_cents)}
                          </div>
                          {getSubscriptionBadge(customer.subscription.status)}
                        </div>
                      ) : (
                        <span className="text-sm text-theme-secondary">No subscription</span>
                      )}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      {getStatusBadge(customer.status)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {formatDate(customer.created_at)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {customer.mrr === 0 ? '$0' : formatCurrency(customer.mrr)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      <div className="flex items-center gap-2">
                        <select
                          value={customer.status}
                          onChange={(e) => handleStatusChange(customer.id, e.target.value)}
                          className="select-theme text-xs"
                        >
                          <option value="active">Active</option>
                          <option value="suspended">Suspended</option>
                          <option value="cancelled">Cancelled</option>
                        </select>
                        <button className="text-theme-link hover:text-theme-link-hover text-xs">
                          View Details
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
      </div>

      {/* Add Customer Modal */}
      <AddCustomerModal
        isOpen={showAddModal}
        onClose={() => setShowAddModal(false)}
        onSubmit={handleAddCustomer}
        loading={addingCustomer}
      />
    </PageContainer>
  );
};

// Add Customer Modal Component
interface AddCustomerModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: CreateCustomerRequest) => Promise<void>;
  loading: boolean;
}

const AddCustomerModal: React.FC<AddCustomerModalProps> = ({ isOpen, onClose, onSubmit, loading }) => {
  const [formData, setFormData] = useState<CreateCustomerRequest>({
    name: '',
    first_name: '',
    last_name: '',
    email: '',
    subdomain: ''
  });
  const [errors, setErrors] = useState<Record<string, string>>({});

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
    // Clear error when field is edited
    if (errors[name]) {
      setErrors(prev => ({ ...prev, [name]: '' }));
    }
  };

  const validate = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Account name is required';
    }
    if (!formData.first_name.trim()) {
      newErrors.first_name = 'First name is required';
    }
    if (!formData.last_name.trim()) {
      newErrors.last_name = 'Last name is required';
    }
    if (!formData.email.trim()) {
      newErrors.email = 'Email is required';
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) {
      newErrors.email = 'Invalid email format';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (validate()) {
      await onSubmit(formData);
    }
  };

  const resetForm = () => {
    setFormData({ name: '', first_name: '', last_name: '', email: '', subdomain: '' });
    setErrors({});
  };

  // Reset form when modal closes
  React.useEffect(() => {
    if (!isOpen) {
      resetForm();
    }
  }, [isOpen]);

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Add New Customer" size="md">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label htmlFor="name" className="block text-sm font-medium text-theme-primary mb-1">
            Account Name *
          </label>
          <Input
            id="name"
            name="name"
            value={formData.name}
            onChange={handleChange}
            placeholder="Company or organization name"
            error={errors.name}
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label htmlFor="first_name" className="block text-sm font-medium text-theme-primary mb-1">
              First Name *
            </label>
            <Input
              id="first_name"
              name="first_name"
              value={formData.first_name}
              onChange={handleChange}
              placeholder="First name"
              error={errors.first_name}
            />
          </div>
          <div>
            <label htmlFor="last_name" className="block text-sm font-medium text-theme-primary mb-1">
              Last Name *
            </label>
            <Input
              id="last_name"
              name="last_name"
              value={formData.last_name}
              onChange={handleChange}
              placeholder="Last name"
              error={errors.last_name}
            />
          </div>
        </div>

        <div>
          <label htmlFor="email" className="block text-sm font-medium text-theme-primary mb-1">
            Email Address *
          </label>
          <Input
            id="email"
            name="email"
            type="email"
            value={formData.email}
            onChange={handleChange}
            placeholder="user@example.com"
            error={errors.email}
          />
        </div>

        <div>
          <label htmlFor="subdomain" className="block text-sm font-medium text-theme-primary mb-1">
            Subdomain (Optional)
          </label>
          <Input
            id="subdomain"
            name="subdomain"
            value={formData.subdomain}
            onChange={handleChange}
            placeholder="company-name"
          />
          <p className="text-xs text-theme-tertiary mt-1">
            This will be used for the customer's unique URL
          </p>
        </div>

        <div className="flex justify-end gap-3 pt-4 border-t border-theme">
          <Button type="button" variant="outline" onClick={onClose} disabled={loading}>
            Cancel
          </Button>
          <Button type="submit" variant="primary" disabled={loading}>
            {loading ? 'Creating...' : 'Create Customer'}
          </Button>
        </div>
      </form>
    </Modal>
  );
};