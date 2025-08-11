import React, { useState, useEffect, useCallback } from 'react';
import { accountsApi, Account, AccountFormData, AccountStats } from '../../services/accountsApi';
import { Button } from '../../components/ui/Button';
import { FormField } from '../../components/ui/FormField';
import { Modal } from '../../components/ui/Modal';
import { Badge } from '../../components/ui/Badge';
import { LoadingSpinner } from '../../components/ui/LoadingSpinner';

interface AccountsPageProps {}

const AccountsPage: React.FC<AccountsPageProps> = () => {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [currentAccount, setCurrentAccount] = useState<Account | null>(null);
  const [accountStats, setAccountStats] = useState<AccountStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedAccount, setSelectedAccount] = useState<Account | null>(null);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showAdminModal, setShowAdminModal] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);
  const [isAdmin, setIsAdmin] = useState(false);

  // Form state
  const [formData, setFormData] = useState<AccountFormData>({
    name: '',
    subdomain: '',
    billing_email: '',
    phone: '',
    timezone: 'UTC',
    settings: {}
  });
  const [formErrors, setFormErrors] = useState<string[]>([]);

  // Load account data
  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      
      // Always load current account
      const currentResponse = await accountsApi.getCurrentAccount();
      if (currentResponse.success) {
        setCurrentAccount(currentResponse.data);
      } else {
        throw new Error('Failed to load current account');
      }

      // Try to load all accounts (admin only) and stats
      try {
        const [allAccountsResponse, statsResponse] = await Promise.all([
          accountsApi.getAllAccounts(),
          accountsApi.getAccountStats()
        ]);
        
        if (allAccountsResponse.success) {
          setAccounts(allAccountsResponse.data);
        } else {
          setAccounts([currentResponse.data]);
        }
        
        if (statsResponse.success) {
          setAccountStats(statsResponse.data);
        }
        
        setIsAdmin(true);
      } catch (adminErr) {
        // User doesn't have admin permissions - show only current account
        console.warn('Admin access not available:', adminErr);
        setAccounts([currentResponse.data]);
        setIsAdmin(false);
      }
    } catch (err) {
      console.error('Error loading accounts:', err);
      setError('Failed to load accounts. Please check your connection and try again.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  // Handle form changes
  const handleFormChange = (field: keyof AccountFormData, value: string | Record<string, any>) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    // Clear form errors when user starts typing
    if (formErrors.length > 0) {
      setFormErrors([]);
    }
  };

  // Reset form
  const resetForm = () => {
    setFormData({
      name: '',
      subdomain: '',
      billing_email: '',
      phone: '',
      timezone: 'UTC',
      settings: {}
    });
    setFormErrors([]);
    setSelectedAccount(null);
  };

  // Handle update account
  const handleUpdateAccount = async () => {
    if (!selectedAccount) return;

    const errors = accountsApi.validateAccountData(formData);
    if (errors.length > 0) {
      setFormErrors(errors);
      return;
    }

    try {
      setActionLoading(true);
      let response;

      // Use appropriate API method based on whether it's current account or admin action
      if (selectedAccount.id === currentAccount?.id) {
        response = await accountsApi.updateAccount(formData);
      } else if (isAdmin) {
        response = await accountsApi.updateAccountById(selectedAccount.id, formData);
      } else {
        throw new Error('Insufficient permissions');
      }
      
      if (response.success) {
        await loadData();
        setShowEditModal(false);
        setShowAdminModal(false);
        resetForm();
      } else {
        setFormErrors([response.message || 'Failed to update account']);
      }
    } catch (err) {
      console.error('Error updating account:', err);
      setFormErrors(['Failed to update account. Please try again.']);
    } finally {
      setActionLoading(false);
    }
  };

  // Handle account status actions (admin only)
  const handleAccountAction = async (account: Account, action: 'suspend' | 'activate' | 'cancel', reason?: string) => {
    if (!isAdmin) return;

    try {
      setActionLoading(true);
      let response;

      switch (action) {
        case 'suspend':
          response = await accountsApi.suspendAccount(account.id, reason || 'Suspended by administrator');
          break;
        case 'activate':
          response = await accountsApi.activateAccount(account.id);
          break;
        case 'cancel':
          response = await accountsApi.cancelAccount(account.id, reason || 'Cancelled by administrator');
          break;
      }

      if (response.success) {
        await loadData();
      } else {
        setError(response.message || `Failed to ${action} account`);
      }
    } catch (err) {
      console.error(`Error ${action} account:`, err);
      setError(`Failed to ${action} account. Please try again.`);
    } finally {
      setActionLoading(false);
    }
  };

  // Open edit modal for current account
  const openEditModal = (account: Account) => {
    setSelectedAccount(account);
    setFormData({
      name: account.name,
      subdomain: account.subdomain,
      billing_email: account.billing_email || '',
      phone: account.phone || '',
      timezone: account.timezone,
      settings: account.settings || {}
    });
    setShowEditModal(true);
  };

  // Open admin modal for other accounts
  const openAdminModal = (account: Account) => {
    setSelectedAccount(account);
    setFormData({
      name: account.name,
      subdomain: account.subdomain,
      billing_email: account.billing_email || '',
      phone: account.phone || '',
      timezone: account.timezone,
      settings: account.settings || {}
    });
    setShowAdminModal(true);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-64">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  return (
    <div className="px-4 sm:px-6 lg:px-8 py-8 bg-theme-background min-h-screen">
      {/* Page Header */}
      <div className="mb-8">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold text-theme-primary">Account Management</h1>
            <p className="text-theme-secondary mt-1">
              {isAdmin ? 'Manage all accounts in the system' : 'Manage your account settings'}
            </p>
          </div>
        </div>

        {/* Admin Stats Cards */}
        {isAdmin && accountStats && (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-6 gap-4 mt-6">
            <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
              <div className="text-2xl font-semibold text-theme-primary">{accountStats.total_accounts}</div>
              <div className="text-theme-secondary text-sm">Total Accounts</div>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
              <div className="text-2xl font-semibold text-green-600">{accountStats.active_accounts}</div>
              <div className="text-theme-secondary text-sm">Active Accounts</div>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
              <div className="text-2xl font-semibold text-red-600">{accountStats.suspended_accounts}</div>
              <div className="text-theme-secondary text-sm">Suspended</div>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
              <div className="text-2xl font-semibold text-blue-600">{accountStats.trial_accounts}</div>
              <div className="text-theme-secondary text-sm">Trial Accounts</div>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
              <div className="text-2xl font-semibold text-purple-600">{accountStats.paying_accounts}</div>
              <div className="text-theme-secondary text-sm">Paying Accounts</div>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
              <div className="text-2xl font-semibold text-green-700">${(accountStats.total_mrr / 100).toFixed(0)}</div>
              <div className="text-theme-secondary text-sm">Total MRR</div>
            </div>
          </div>
        )}
      </div>

      {/* Error Display */}
      {error && (
        <div className="bg-orange-50 border border-orange-200 text-orange-700 px-4 py-3 rounded mb-4">
          <div className="flex">
            <div className="flex-shrink-0">
              <span className="text-orange-400">⚠️</span>
            </div>
            <div className="ml-3">
              <p className="text-sm">
                {error}
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Accounts Table */}
      <div className="bg-theme-surface rounded-lg shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-theme">
            <thead className="bg-theme-background">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Account
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Owner
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Users
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Subscription
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Created
                </th>
                <th className="px-6 py-3 text-right text-xs font-medium text-theme-secondary uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {accounts.map((account) => (
                <tr key={account.id} className="hover:bg-theme-surface-hover">
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center">
                      <div className="flex-shrink-0 h-10 w-10">
                        <div className="h-10 w-10 rounded-full bg-theme-interactive-primary flex items-center justify-center">
                          <span className="text-white text-sm font-medium">
                            {account.name[0]}
                          </span>
                        </div>
                      </div>
                      <div className="ml-4">
                        <div className="text-sm font-medium text-theme-primary">
                          {account.name}
                          {account.id === currentAccount?.id && (
                            <Badge variant="info" className="ml-2">Current</Badge>
                          )}
                        </div>
                        <div className="text-sm text-theme-secondary">
                          {accountsApi.formatSubdomain(account.subdomain)}
                        </div>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-theme-primary">{account.owner.full_name}</div>
                    <div className="text-sm text-theme-secondary">{account.owner.email}</div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <Badge className={accountsApi.getStatusColor(account.status)}>
                      {account.status}
                    </Badge>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                    {account.users_count} user{account.users_count !== 1 ? 's' : ''}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    {account.subscription ? (
                      <div>
                        <div className="text-sm font-medium text-theme-primary">
                          {account.subscription.plan_name}
                        </div>
                        <Badge 
                          className={accountsApi.getStatusColor(account.subscription.status)}
                          variant={account.subscription.status === 'active' ? 'success' : 'default'}
                        >
                          {account.subscription.status}
                        </Badge>
                      </div>
                    ) : (
                      <span className="text-theme-secondary">No subscription</span>
                    )}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                    {new Date(account.created_at).toLocaleDateString()}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <div className="flex items-center justify-end space-x-2">
                      <Button
                        variant="secondary"
                        size="sm"
                        onClick={() => {
                          if (account.id === currentAccount?.id) {
                            openEditModal(account);
                          } else if (isAdmin) {
                            openAdminModal(account);
                          }
                        }}
                      >
                        {account.id === currentAccount?.id ? 'Edit' : 'Manage'}
                      </Button>
                      
                      {/* Admin Actions */}
                      {isAdmin && account.id !== currentAccount?.id && (
                        <>
                          {account.status === 'suspended' ? (
                            <Button
                              variant="secondary"
                              size="sm"
                              onClick={() => handleAccountAction(account, 'activate')}
                              disabled={actionLoading}
                            >
                              Activate
                            </Button>
                          ) : account.status === 'active' ? (
                            <Button
                              variant="secondary"
                              size="sm"
                              onClick={() => handleAccountAction(account, 'suspend', 'Suspended by administrator')}
                              disabled={actionLoading}
                            >
                              Suspend
                            </Button>
                          ) : null}

                          {account.status !== 'cancelled' && (
                            <Button
                              variant="danger"
                              size="sm"
                              onClick={() => handleAccountAction(account, 'cancel', 'Cancelled by administrator')}
                              disabled={actionLoading}
                            >
                              Cancel
                            </Button>
                          )}
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {accounts.length === 0 && (
            <div className="text-center py-12">
              <div className="text-theme-secondary">No accounts found.</div>
            </div>
          )}
        </div>
      </div>

      {/* Edit Current Account Modal */}
      <Modal
        isOpen={showEditModal}
        onClose={() => {
          setShowEditModal(false);
          resetForm();
        }}
        title="Edit Account Settings"
        maxWidth="md"
      >
        <div className="space-y-4">
          {formErrors.length > 0 && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
              <ul className="list-disc list-inside">
                {formErrors.map((error, index) => (
                  <li key={index}>{error}</li>
                ))}
              </ul>
            </div>
          )}

          <FormField
            label="Account Name"
            type="text"
            value={formData.name}
            onChange={(value) => handleFormChange('name', value)}
            required
          />

          <FormField
            label="Subdomain"
            type="text"
            value={formData.subdomain}
            onChange={(value) => handleFormChange('subdomain', value)}
            helpText={formData.subdomain ? `Your account will be available at ${formData.subdomain}.powernode.com` : 'Choose a unique subdomain for your account'}
          />

          <FormField
            label="Billing Email"
            type="email"
            value={formData.billing_email}
            onChange={(value) => handleFormChange('billing_email', value)}
            helpText="Email address for billing notifications"
          />

          <FormField
            label="Phone"
            type="tel"
            value={formData.phone}
            onChange={(value) => handleFormChange('phone', value)}
          />

          <FormField
            label="Timezone"
            type="select"
            value={formData.timezone}
            onChange={(value) => handleFormChange('timezone', value)}
            options={accountsApi.getAvailableTimezones()}
            required
          />

          <div className="flex justify-end space-x-3 mt-6">
            <Button
              variant="secondary"
              onClick={() => {
                setShowEditModal(false);
                resetForm();
              }}
            >
              Cancel
            </Button>
            <Button
              onClick={handleUpdateAccount}
              disabled={actionLoading}
            >
              {actionLoading ? 'Updating...' : 'Update Account'}
            </Button>
          </div>
        </div>
      </Modal>

      {/* Admin Account Management Modal */}
      <Modal
        isOpen={showAdminModal}
        onClose={() => {
          setShowAdminModal(false);
          resetForm();
        }}
        title={`Manage Account: ${selectedAccount?.name}`}
        maxWidth="md"
      >
        <div className="space-y-4">
          {formErrors.length > 0 && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
              <ul className="list-disc list-inside">
                {formErrors.map((error, index) => (
                  <li key={index}>{error}</li>
                ))}
              </ul>
            </div>
          )}

          <div className="bg-yellow-50 border border-yellow-200 text-yellow-700 px-4 py-3 rounded">
            <strong>Admin Mode:</strong> You are editing another account's settings.
          </div>

          <FormField
            label="Account Name"
            type="text"
            value={formData.name}
            onChange={(value) => handleFormChange('name', value)}
            required
          />

          <FormField
            label="Subdomain"
            type="text"
            value={formData.subdomain}
            onChange={(value) => handleFormChange('subdomain', value)}
            helpText={formData.subdomain ? `Account will be available at ${formData.subdomain}.powernode.com` : 'Choose a unique subdomain for this account'}
          />

          <FormField
            label="Billing Email"
            type="email"
            value={formData.billing_email}
            onChange={(value) => handleFormChange('billing_email', value)}
            helpText="Email address for billing notifications"
          />

          <FormField
            label="Phone"
            type="tel"
            value={formData.phone}
            onChange={(value) => handleFormChange('phone', value)}
          />

          <FormField
            label="Timezone"
            type="select"
            value={formData.timezone}
            onChange={(value) => handleFormChange('timezone', value)}
            options={accountsApi.getAvailableTimezones()}
            required
          />

          <div className="flex justify-end space-x-3 mt-6">
            <Button
              variant="secondary"
              onClick={() => {
                setShowAdminModal(false);
                resetForm();
              }}
            >
              Cancel
            </Button>
            <Button
              onClick={handleUpdateAccount}
              disabled={actionLoading}
            >
              {actionLoading ? 'Updating...' : 'Update Account'}
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  );
};

export default AccountsPage;