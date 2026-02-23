import React, { useState, useRef, useEffect } from 'react';
import { useSelector } from 'react-redux';
import {
  BuildingOfficeIcon,
  ChevronUpDownIcon,
  CheckIcon,
  ArrowPathIcon,
  HomeIcon,
} from '@heroicons/react/24/outline';
import { RootState } from '@/shared/services';
import { accountSwitcherApi, AccessibleAccount } from '../services/accountSwitcherApi';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface AccountSwitcherProps {
  className?: string;
}

export const AccountSwitcher: React.FC<AccountSwitcherProps> = ({ className = '' }) => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();

  const [isOpen, setIsOpen] = useState(false);
  const [accounts, setAccounts] = useState<AccessibleAccount[]>([]);
  const [loading, setLoading] = useState(false);
  const [switching, setSwitching] = useState(false);
  const [currentAccountId, setCurrentAccountId] = useState<string | null>(null);
  const [primaryAccountId, setPrimaryAccountId] = useState<string | null>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Load accessible accounts when dropdown opens
  useEffect(() => {
    if (isOpen && accounts.length === 0) {
      loadAccounts();
    }
  }, [isOpen]);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const loadAccounts = async () => {
    setLoading(true);
    try {
      const response = await accountSwitcherApi.getAccessibleAccounts();
      setAccounts(response.accounts);
      setCurrentAccountId(response.current_account_id);
      setPrimaryAccountId(response.primary_account_id);
    } catch (_error) {
      showNotification('Failed to load accessible accounts', 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleSwitchAccount = async (account: AccessibleAccount) => {
    if (account.is_current) {
      setIsOpen(false);
      return;
    }

    setSwitching(true);
    try {
      const response = await accountSwitcherApi.switchAccount(account.id);

      // Access token is managed by Redux state; refresh token is in HttpOnly cookie
      // Page reload below will bootstrap auth from cookie

      showNotification(`Switched to ${account.name}`, 'success');

      // Reload the page to refresh the entire app state with new account context
      window.location.reload();
    } catch (_error) {
      showNotification('Failed to switch account', 'error');
    } finally {
      setSwitching(false);
      setIsOpen(false);
    }
  };

  const handleSwitchToPrimary = async () => {
    if (currentAccountId === primaryAccountId) {
      setIsOpen(false);
      return;
    }

    setSwitching(true);
    try {
      const response = await accountSwitcherApi.switchToPrimary();

      // Access token is managed by Redux state; refresh token is in HttpOnly cookie
      // Page reload below will bootstrap auth from cookie

      showNotification('Switched back to primary account', 'success');

      // Reload the page to refresh the entire app state
      window.location.reload();
    } catch (_error) {
      showNotification('Failed to switch to primary account', 'error');
    } finally {
      setSwitching(false);
      setIsOpen(false);
    }
  };

  // Only show if user has access to multiple accounts
  const currentAccount = accounts.find((a) => a.is_current) || {
    name: user?.account?.name,
    is_primary: true,
  };

  const isOnDelegatedAccount = currentAccountId !== primaryAccountId && currentAccountId;

  // Get role badge color
  const getRoleBadgeColor = (role: string) => {
    switch (role) {
      case 'owner':
        return 'bg-theme-success/20 text-theme-success dark:bg-theme-success/30 dark:text-theme-success';
      case 'delegated':
      case 'Admin':
        return 'bg-theme-info/20 text-theme-info dark:bg-theme-info/30 dark:text-theme-info';
      default:
        return 'bg-theme-surface text-theme-primary dark:bg-theme-background/30 dark:text-theme-secondary';
    }
  };

  return (
    <div className={`relative ${className}`} ref={dropdownRef}>
      {/* Switcher Button */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className={`
          flex items-center space-x-2 px-3 py-2 rounded-lg border transition-all duration-200
          ${isOnDelegatedAccount
            ? 'border-theme-warning bg-theme-warning/10 dark:bg-theme-warning/20 hover:bg-theme-warning/20 dark:hover:bg-theme-warning/30'
            : 'border-theme bg-theme-surface hover:bg-theme-surface-hover'
          }
        `}
      >
        <BuildingOfficeIcon className={`h-5 w-5 ${isOnDelegatedAccount ? 'text-theme-warning' : 'text-theme-secondary'}`} />
        <div className="text-left hidden sm:block">
          <p className="text-sm font-medium text-theme-primary truncate max-w-[120px]">
            {currentAccount.name}
          </p>
          {isOnDelegatedAccount && (
            <p className="text-xs text-theme-warning">
              Delegated Access
            </p>
          )}
        </div>
        <ChevronUpDownIcon className="h-4 w-4 text-theme-secondary" />
      </button>

      {/* Dropdown Menu */}
      {isOpen && (
        <div className="absolute right-0 mt-2 w-80 bg-theme-surface rounded-xl shadow-xl border border-theme z-50 overflow-hidden">
          {/* Header */}
          <div className="px-4 py-3 border-b border-theme bg-theme-background">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-theme-primary">Switch Account</span>
              {switching && (
                <ArrowPathIcon className="h-4 w-4 text-theme-secondary animate-spin" />
              )}
            </div>
          </div>

          {/* Account List */}
          <div className="max-h-64 overflow-y-auto">
            {loading ? (
              <div className="px-4 py-6 text-center">
                <ArrowPathIcon className="h-6 w-6 text-theme-secondary animate-spin mx-auto" />
                <p className="text-sm text-theme-secondary mt-2">Loading accounts...</p>
              </div>
            ) : accounts.length === 0 ? (
              <div className="px-4 py-6 text-center">
                <p className="text-sm text-theme-secondary">No other accounts available</p>
              </div>
            ) : (
              <div className="py-1">
                {accounts.map((account) => (
                  <button
                    key={account.id}
                    onClick={() => handleSwitchAccount(account)}
                    disabled={switching}
                    className={`
                      w-full px-4 py-3 flex items-center justify-between text-left
                      hover:bg-theme-surface-hover transition-colors duration-150
                      ${account.is_current ? 'bg-theme-background' : ''}
                      disabled:opacity-50 disabled:cursor-not-allowed
                    `}
                  >
                    <div className="flex items-center space-x-3">
                      <div className={`
                        h-10 w-10 rounded-lg flex items-center justify-center
                        ${account.is_primary
                          ? 'bg-theme-success/20 dark:bg-theme-success/30'
                          : 'bg-theme-info/20 dark:bg-theme-info/30'
                        }
                      `}>
                        {account.is_primary ? (
                          <HomeIcon className="h-5 w-5 text-theme-success" />
                        ) : (
                          <BuildingOfficeIcon className="h-5 w-5 text-theme-info" />
                        )}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center space-x-2">
                          <p className="text-sm font-medium text-theme-primary truncate">
                            {account.name}
                          </p>
                          <span className={`px-1.5 py-0.5 text-xs rounded ${getRoleBadgeColor(account.role)}`}>
                            {account.role}
                          </span>
                        </div>
                        <div className="flex items-center space-x-2 mt-0.5">
                          {account.subscription && (
                            <span className="text-xs text-theme-tertiary">
                              {account.subscription.plan_name}
                            </span>
                          )}
                          {account.delegation?.expires_at && (
                            <span className="text-xs text-theme-warning">
                              Expires: {new Date(account.delegation.expires_at).toLocaleDateString()}
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                    {account.is_current && (
                      <CheckIcon className="h-5 w-5 text-theme-success" />
                    )}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Return to Primary */}
          {isOnDelegatedAccount && (
            <div className="border-t border-theme">
              <button
                onClick={handleSwitchToPrimary}
                disabled={switching}
                className="w-full px-4 py-3 flex items-center space-x-3 text-left hover:bg-theme-surface-hover transition-colors disabled:opacity-50"
              >
                <div className="h-10 w-10 rounded-lg bg-theme-success/20 dark:bg-theme-success/30 flex items-center justify-center">
                  <HomeIcon className="h-5 w-5 text-theme-success" />
                </div>
                <div>
                  <p className="text-sm font-medium text-theme-primary">Return to Primary Account</p>
                  <p className="text-xs text-theme-tertiary">Exit delegated access</p>
                </div>
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default AccountSwitcher;
