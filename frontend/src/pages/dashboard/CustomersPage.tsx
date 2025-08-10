import React, { useState, useEffect, useCallback } from 'react';
import { useCustomerWebSocket } from '../../hooks/useCustomerWebSocket';
import { customersApi } from '../../services/customersApi';

export const CustomersPage: React.FC = () => {
  const {
    customers,
    stats,
    searchResults,
    error,
    loadCustomers,
    searchCustomers,
    updateCustomerStatus
  } = useCustomerWebSocket();

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
      } catch (error) {
        console.error('Failed to load customers:', error);
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

  const handleStatusChange = async (customerId: string, newStatus: string) => {
    await updateCustomerStatus(customerId, newStatus);
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
    const colors = customersApi.getStatusColor(status);
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
        {customersApi.getStatusText(status)}
      </span>
    );
  };

  const getSubscriptionBadge = (status: string) => {
    const colors = customersApi.getSubscriptionStatusColor(status);
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
        {customersApi.formatSubscriptionStatus(status)}
      </span>
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">Customers</h1>
          <p className="text-theme-secondary">
            Manage your customer accounts and their subscriptions.
          </p>
        </div>
        <button className="btn-theme btn-theme-primary">
          Add Customer
        </button>
      </div>

      {error && (
        <div className="bg-theme-error text-theme-error card-theme p-4">
          <p className="text-theme-error text-sm">{error}</p>
        </div>
      )}

      {/* Customer Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-6">
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Total Customers</h3>
          <p className="text-2xl font-bold text-theme-primary">{formatNumber(stats.total_customers)}</p>
          <p className="text-xs text-theme-secondary mt-1">All time</p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Active Customers</h3>
          <p className="text-2xl font-bold text-theme-primary">{formatNumber(stats.active_customers)}</p>
          <p className="text-xs text-theme-success mt-1">Currently active</p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Active Subscriptions</h3>
          <p className="text-2xl font-bold text-theme-primary">{formatNumber(stats.active_subscriptions)}</p>
          <p className="text-xs text-theme-success mt-1">Paying customers</p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">New This Month</h3>
          <p className="text-2xl font-bold text-theme-primary">{formatNumber(stats.new_this_month)}</p>
          <p className="text-xs text-theme-info mt-1">New customers</p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Total MRR</h3>
          <p className="text-2xl font-bold text-theme-primary">{customersApi.formatCurrency(stats.total_mrr)}</p>
          <p className="text-xs text-theme-success mt-1">Monthly recurring</p>
        </div>
        <div className="card-theme p-6">
          <h3 className="text-sm font-medium text-theme-secondary">Churn Rate</h3>
          <p className="text-2xl font-bold text-theme-primary">{stats.churn_rate.toFixed(1)}%</p>
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
                  <td colSpan={6} className="px-6 py-12 text-center">
                    <div className="flex justify-center">
                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-link"></div>
                    </div>
                    <p className="text-theme-secondary mt-2">Loading customers...</p>
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
                            {customersApi.formatCurrency(customer.subscription.plan.price_cents)}
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
                      {customersApi.formatJoinDate(customer.created_at)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {customersApi.calculateMrrDisplay(customer.mrr)}
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
  );
};