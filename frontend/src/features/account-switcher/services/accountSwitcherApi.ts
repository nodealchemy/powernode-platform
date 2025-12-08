import apiClient from '@/shared/services/apiClient';

export interface AccessibleAccount {
  id: string;
  name: string;
  subdomain?: string;
  status: string;
  role: string;
  is_primary: boolean;
  is_current: boolean;
  delegation?: {
    id: string;
    expires_at?: string;
    permissions: string;
  };
  subscription?: {
    plan_name: string;
    status: string;
  };
}

export interface AccessibleAccountsResponse {
  accounts: AccessibleAccount[];
  current_account_id: string;
  primary_account_id: string;
}

export interface SwitchAccountResponse {
  access_token: string;
  refresh_token: string;
  expires_at: string;
  account: AccessibleAccount;
  permissions: string[];
  user: {
    id: string;
    email: string;
    name: string;
    account: {
      id: string;
      name: string;
      status: string;
    };
  };
}

export const accountSwitcherApi = {
  // Get all accessible accounts for the current user
  getAccessibleAccounts: async (): Promise<AccessibleAccountsResponse> => {
    const response = await apiClient.get('/api/v1/accounts/accessible');
    return response.data.data;
  },

  // Switch to a different account
  switchAccount: async (accountId: string): Promise<SwitchAccountResponse> => {
    const response = await apiClient.post('/api/v1/accounts/switch', {
      account_id: accountId,
    });
    return response.data.data;
  },

  // Switch back to primary account
  switchToPrimary: async (): Promise<SwitchAccountResponse> => {
    const response = await apiClient.post('/api/v1/accounts/switch_to_primary');
    return response.data.data;
  },
};

export default accountSwitcherApi;
