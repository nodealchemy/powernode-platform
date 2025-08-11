import React, { useState, useEffect } from 'react';
import { delegationApi, DELEGATION_PERMISSIONS } from '../../services/delegationApi';

interface CreateDelegationModalProps {
  onClose: () => void;
  onCreate: (data: any) => void;
}

interface Account {
  id: string;
  name: string;
  domain?: string;
}

interface User {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  roles: string[];
}

export const CreateDelegationModal: React.FC<CreateDelegationModalProps> = ({ onClose, onCreate }) => {
  const [step, setStep] = useState(1);
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    targetAccountId: '',
    permissions: [] as string[],
    userIds: [] as string[],
    expiresAt: '',
  });
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<Account[]>([]);
  const [selectedAccount, setSelectedAccount] = useState<Account | null>(null);
  const [availableUsers, setAvailableUsers] = useState<User[]>([]);
  const [searching, setSearching] = useState(false);

  useEffect(() => {
    if (searchQuery.length >= 3) {
      const timeoutId = setTimeout(() => {
        searchAccounts();
      }, 300);
      return () => clearTimeout(timeoutId);
    }
  }, [searchQuery]);

  const searchAccounts = async () => {
    try {
      setSearching(true);
      const data = await delegationApi.searchAccounts(searchQuery);
      setSearchResults(data.accounts || []);
    } catch (error) {
      console.error('Failed to search accounts:', error);
    } finally {
      setSearching(false);
    }
  };

  const loadAvailableUsers = async (accountId: string) => {
    try {
      const data = await delegationApi.getAvailableUsers(accountId);
      setAvailableUsers(data.users || []);
    } catch (error) {
      console.error('Failed to load users:', error);
    }
  };

  const handleAccountSelect = (account: Account) => {
    setSelectedAccount(account);
    setFormData({ ...formData, targetAccountId: account.id });
    loadAvailableUsers(account.id);
    setSearchQuery('');
    setSearchResults([]);
  };

  const handlePermissionToggle = (permission: string) => {
    setFormData(prev => ({
      ...prev,
      permissions: prev.permissions.includes(permission)
        ? prev.permissions.filter(p => p !== permission)
        : [...prev.permissions, permission],
    }));
  };

  const handleUserToggle = (userId: string) => {
    setFormData(prev => ({
      ...prev,
      userIds: prev.userIds.includes(userId)
        ? prev.userIds.filter(id => id !== userId)
        : [...prev.userIds, userId],
    }));
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onCreate(formData);
  };

  const isStepValid = () => {
    switch (step) {
      case 1:
        return formData.name && formData.description && formData.targetAccountId;
      case 2:
        return formData.permissions.length > 0;
      case 3:
        return formData.userIds.length > 0;
      default:
        return false;
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-theme-surface rounded-lg w-full max-w-2xl max-h-[90vh] overflow-hidden">
        <div className="p-6 border-b border-theme">
          <div className="flex items-center justify-between">
            <h2 className="text-xl font-semibold text-theme-primary">Create Delegation</h2>
            <button
              onClick={onClose}
              className="text-theme-secondary hover:text-theme-primary"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          
          {/* Step Indicator */}
          <div className="flex items-center justify-center mt-6 space-x-2">
            {[1, 2, 3].map((s) => (
              <React.Fragment key={s}>
                <div className={`flex items-center justify-center w-8 h-8 rounded-full ${
                  s === step ? 'bg-theme-interactive-primary text-white' :
                  s < step ? 'bg-theme-success text-white' :
                  'bg-theme-surface-hover text-theme-secondary'
                }`}>
                  {s < step ? '✓' : s}
                </div>
                {s < 3 && (
                  <div className={`w-16 h-1 ${
                    s < step ? 'bg-theme-success' : 'bg-theme-surface-hover'
                  }`} />
                )}
              </React.Fragment>
            ))}
          </div>
          <div className="flex justify-center mt-2 text-sm text-theme-secondary">
            {step === 1 && 'Basic Information'}
            {step === 2 && 'Select Permissions'}
            {step === 3 && 'Add Users'}
          </div>
        </div>

        <form onSubmit={handleSubmit} className="p-6 overflow-y-auto max-h-[calc(90vh-200px)]">
          {/* Step 1: Basic Information */}
          {step === 1 && (
            <div className="space-y-6">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Delegation Name
                </label>
                <input
                  type="text"
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
                  placeholder="e.g., Support Team Access"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Description
                </label>
                <textarea
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
                  rows={3}
                  placeholder="Describe the purpose of this delegation..."
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Target Account
                </label>
                {selectedAccount ? (
                  <div className="bg-theme-background rounded-lg p-4 border border-theme">
                    <div className="flex items-center justify-between">
                      <div>
                        <h4 className="font-medium text-theme-primary">{selectedAccount.name}</h4>
                        {selectedAccount.domain && (
                          <p className="text-sm text-theme-secondary">{selectedAccount.domain}</p>
                        )}
                      </div>
                      <button
                        type="button"
                        onClick={() => {
                          setSelectedAccount(null);
                          setFormData({ ...formData, targetAccountId: '' });
                        }}
                        className="text-theme-error hover:text-theme-error-hover"
                      >
                        Remove
                      </button>
                    </div>
                  </div>
                ) : (
                  <div>
                    <input
                      type="text"
                      value={searchQuery}
                      onChange={(e) => setSearchQuery(e.target.value)}
                      className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
                      placeholder="Search for an account..."
                    />
                    {searching && (
                      <div className="mt-2 text-sm text-theme-secondary">Searching...</div>
                    )}
                    {searchResults.length > 0 && (
                      <div className="mt-2 bg-theme-background rounded-lg border border-theme max-h-48 overflow-y-auto">
                        {searchResults.map((account) => (
                          <button
                            key={account.id}
                            type="button"
                            onClick={() => handleAccountSelect(account)}
                            className="w-full text-left px-4 py-3 hover:bg-theme-surface-hover transition-colors border-b border-theme last:border-b-0"
                          >
                            <div className="font-medium text-theme-primary">{account.name}</div>
                            {account.domain && (
                              <div className="text-sm text-theme-secondary">{account.domain}</div>
                            )}
                          </button>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Expiration Date (Optional)
                </label>
                <input
                  type="datetime-local"
                  value={formData.expiresAt}
                  onChange={(e) => setFormData({ ...formData, expiresAt: e.target.value })}
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
                />
                <p className="text-xs text-theme-secondary mt-1">
                  Leave empty for no expiration
                </p>
              </div>
            </div>
          )}

          {/* Step 2: Select Permissions */}
          {step === 2 && (
            <div className="space-y-6">
              <div>
                <h3 className="text-lg font-medium text-theme-primary mb-4">Select Permissions</h3>
                <p className="text-sm text-theme-secondary mb-4">
                  Choose which permissions to grant to the delegated users
                </p>
                <div className="space-y-3">
                  {DELEGATION_PERMISSIONS.map((permission) => (
                    <label
                      key={permission.key}
                      className="flex items-start space-x-3 p-3 bg-theme-background rounded-lg hover:bg-theme-surface-hover cursor-pointer"
                    >
                      <input
                        type="checkbox"
                        checked={formData.permissions.includes(permission.key)}
                        onChange={() => handlePermissionToggle(permission.key)}
                        className="mt-1 rounded border-theme text-theme-interactive-primary"
                      />
                      <div className="flex-1">
                        <div className="font-medium text-theme-primary">{permission.label}</div>
                        <div className="text-sm text-theme-secondary">{permission.description}</div>
                      </div>
                    </label>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* Step 3: Add Users */}
          {step === 3 && (
            <div className="space-y-6">
              <div>
                <h3 className="text-lg font-medium text-theme-primary mb-4">Add Users</h3>
                <p className="text-sm text-theme-secondary mb-4">
                  Select users from your account who will have delegated access
                </p>
                <div className="space-y-3">
                  {availableUsers.length > 0 ? (
                    availableUsers.map((user) => (
                      <label
                        key={user.id}
                        className="flex items-center space-x-3 p-3 bg-theme-background rounded-lg hover:bg-theme-surface-hover cursor-pointer"
                      >
                        <input
                          type="checkbox"
                          checked={formData.userIds.includes(user.id)}
                          onChange={() => handleUserToggle(user.id)}
                          className="rounded border-theme text-theme-interactive-primary"
                        />
                        <div className="flex-1">
                          <div className="font-medium text-theme-primary">
                            {user.firstName} {user.lastName}
                          </div>
                          <div className="text-sm text-theme-secondary">
                            {user.email} • {user.roles.join(', ') || 'N/A'}
                          </div>
                        </div>
                      </label>
                    ))
                  ) : (
                    <div className="bg-theme-background rounded-lg p-8 text-center">
                      <p className="text-theme-secondary">No users available</p>
                      <p className="text-sm text-theme-tertiary mt-1">
                        You need to have users in your account to delegate access
                      </p>
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}
        </form>

        <div className="p-6 border-t border-theme bg-theme-background">
          <div className="flex justify-between">
            <button
              type="button"
              onClick={() => step > 1 ? setStep(step - 1) : onClose()}
              className="btn-theme btn-theme-secondary"
            >
              {step === 1 ? 'Cancel' : 'Back'}
            </button>
            <button
              type="button"
              onClick={() => {
                if (step < 3 && isStepValid()) {
                  setStep(step + 1);
                } else if (step === 3 && isStepValid()) {
                  handleSubmit(new Event('submit') as any);
                }
              }}
              disabled={!isStepValid()}
              className="btn-theme btn-theme-primary disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {step === 3 ? 'Create Delegation' : 'Next'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};