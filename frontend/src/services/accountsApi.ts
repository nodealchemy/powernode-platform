import { api } from './api';

export interface Account {
  id: string;
  name: string;
  subdomain: string;
  status: 'active' | 'suspended' | 'cancelled';
  owner_id: string;
  users_count: number;
  billing_email?: string;
  phone?: string;
  timezone: string;
  created_at: string;
  updated_at: string;
  subscription?: {
    id: string;
    plan_name: string;
    status: string;
    current_period_start: string;
    current_period_end: string;
    trial_end?: string | null;
  };
  owner: {
    id: string;
    full_name: string;
    email: string;
  };
  settings: Record<string, any>;
}

export interface AccountFormData {
  name: string;
  subdomain?: string;
  billing_email?: string;
  phone?: string;
  timezone: string;
  settings?: Record<string, any>;
}

export interface AccountStats {
  total_accounts: number;
  active_accounts: number;
  suspended_accounts: number;
  trial_accounts: number;
  paying_accounts: number;
  total_mrr: number;
}

export interface AccountsListResponse {
  success: boolean;
  data: Account[];
  stats?: AccountStats;
}

export interface AccountResponse {
  success: boolean;
  data: Account;
  message?: string;
}

class AccountsApiService {
  // Get current account
  async getCurrentAccount(): Promise<AccountResponse> {
    const response = await api.get('/accounts/current');
    return response.data;
  }

  // Get specific account (admin only for other accounts)
  async getAccount(accountId: string): Promise<AccountResponse> {
    const response = await api.get(`/accounts/${accountId}`);
    return response.data;
  }

  // Update current account
  async updateAccount(accountData: AccountFormData): Promise<AccountResponse> {
    const response = await api.put('/accounts/current', {
      account: accountData
    });
    return response.data;
  }

  // Update specific account (admin only)
  async updateAccountById(accountId: string, accountData: AccountFormData): Promise<AccountResponse> {
    const response = await api.put(`/accounts/${accountId}`, {
      account: accountData
    });
    return response.data;
  }

  // Get all accounts (admin only)
  async getAllAccounts(): Promise<AccountsListResponse> {
    const response = await api.get('/admin/accounts');
    return response.data;
  }

  // Get account statistics (admin only)
  async getAccountStats(): Promise<{ success: boolean; data: AccountStats }> {
    const response = await api.get('/admin/accounts/stats');
    return response.data;
  }

  // Suspend account (admin only)
  async suspendAccount(accountId: string, reason: string): Promise<AccountResponse> {
    const response = await api.put(`/admin/accounts/${accountId}/suspend`, {
      reason: reason
    });
    return response.data;
  }

  // Activate account (admin only)
  async activateAccount(accountId: string): Promise<AccountResponse> {
    const response = await api.put(`/admin/accounts/${accountId}/activate`);
    return response.data;
  }

  // Cancel account (admin only)
  async cancelAccount(accountId: string, reason: string): Promise<AccountResponse> {
    const response = await api.put(`/admin/accounts/${accountId}/cancel`, {
      reason: reason
    });
    return response.data;
  }

  // Get account usage (for current account)
  async getAccountUsage(): Promise<{ success: boolean; data: any }> {
    const response = await api.get('/accounts/usage');
    return response.data;
  }

  // Available timezones
  getAvailableTimezones(): Array<{ value: string; label: string }> {
    return [
      { value: 'UTC', label: 'UTC' },
      { value: 'America/New_York', label: 'Eastern Time (US & Canada)' },
      { value: 'America/Chicago', label: 'Central Time (US & Canada)' },
      { value: 'America/Denver', label: 'Mountain Time (US & Canada)' },
      { value: 'America/Los_Angeles', label: 'Pacific Time (US & Canada)' },
      { value: 'America/Phoenix', label: 'Arizona' },
      { value: 'America/Anchorage', label: 'Alaska' },
      { value: 'Pacific/Honolulu', label: 'Hawaii' },
      { value: 'Europe/London', label: 'London' },
      { value: 'Europe/Berlin', label: 'Berlin' },
      { value: 'Europe/Paris', label: 'Paris' },
      { value: 'Europe/Rome', label: 'Rome' },
      { value: 'Europe/Madrid', label: 'Madrid' },
      { value: 'Europe/Amsterdam', label: 'Amsterdam' },
      { value: 'Asia/Tokyo', label: 'Tokyo' },
      { value: 'Asia/Shanghai', label: 'Shanghai' },
      { value: 'Asia/Singapore', label: 'Singapore' },
      { value: 'Asia/Mumbai', label: 'Mumbai' },
      { value: 'Australia/Sydney', label: 'Sydney' },
      { value: 'Australia/Melbourne', label: 'Melbourne' }
    ];
  }

  // Get status color for UI
  getStatusColor(status: string): string {
    switch (status) {
      case 'active':
        return 'text-theme-success bg-theme-success-background border-theme-success-border';
      case 'suspended':
        return 'text-theme-error bg-theme-error-background border-theme-error-border';
      case 'cancelled':
        return 'text-theme-secondary bg-theme-surface-hover border-theme';
      default:
        return 'text-theme-secondary bg-theme-surface-hover border-theme';
    }
  }

  // Format account subdomain
  formatSubdomain(subdomain: string): string {
    return subdomain ? `${subdomain}.powernode.com` : 'Not set';
  }

  // Validate account form data
  validateAccountData(accountData: AccountFormData): string[] {
    const errors: string[] = [];

    if (!accountData.name || accountData.name.trim().length < 1) {
      errors.push('Account name is required');
    }

    if (accountData.subdomain) {
      if (!/^[a-z0-9-]+$/.test(accountData.subdomain)) {
        errors.push('Subdomain can only contain lowercase letters, numbers, and hyphens');
      }
      if (accountData.subdomain.length < 3) {
        errors.push('Subdomain must be at least 3 characters long');
      }
      if (accountData.subdomain.startsWith('-') || accountData.subdomain.endsWith('-')) {
        errors.push('Subdomain cannot start or end with a hyphen');
      }
    }

    if (accountData.billing_email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(accountData.billing_email)) {
      errors.push('Billing email format is invalid');
    }

    if (!accountData.timezone) {
      errors.push('Timezone is required');
    }

    return errors;
  }

  // Generate random subdomain suggestion
  generateSubdomainSuggestion(accountName: string): string {
    const clean = accountName.toLowerCase()
      .replace(/[^a-z0-9]/g, '')
      .substring(0, 10);
    const random = Math.floor(Math.random() * 1000);
    return `${clean}${random}`;
  }
}

export const accountsApi = new AccountsApiService();