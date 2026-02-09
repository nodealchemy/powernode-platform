import apiClient from '@/shared/services/apiClient';

export interface ConsentPreference {
  granted: boolean;
  required: boolean;
  description: string;
  version?: string;
  granted_at?: string;
  withdrawn_at?: string;
}

export interface ConsentPreferences {
  marketing: ConsentPreference;
  analytics: ConsentPreference;
  cookies: ConsentPreference;
  data_sharing: ConsentPreference;
  third_party: ConsentPreference;
  communications: ConsentPreference;
  newsletter: ConsentPreference;
  promotional: ConsentPreference;
}

export interface DataExportRequest {
  id: string;
  status: 'pending' | 'processing' | 'completed' | 'failed' | 'expired';
  format: 'json' | 'csv' | 'zip';
  export_type: 'full' | 'partial';
  file_size_bytes?: number;
  downloadable: boolean;
  download_token?: string;
  download_token_expires_at?: string;
  created_at: string;
  completed_at?: string;
  expires_at?: string;
}

export interface DataDeletionRequest {
  id: string;
  status: 'pending' | 'approved' | 'processing' | 'completed' | 'rejected' | 'cancelled';
  deletion_type: 'full' | 'partial' | 'anonymize';
  reason?: string;
  can_be_cancelled: boolean;
  in_grace_period: boolean;
  days_until_deletion?: number;
  grace_period_ends_at?: string;
  created_at: string;
  completed_at?: string;
}

export interface TermsAcceptance {
  document_type: string;
  current_version: string;
  accepted: boolean;
  accepted_version?: string;
  accepted_at?: string;
}

export interface CookiePreferences {
  necessary: boolean;
  functional: boolean;
  analytics: boolean;
  marketing: boolean;
  consented_at?: string;
}

export interface PrivacyDashboard {
  consents: ConsentPreferences;
  export_requests: DataExportRequest[];
  deletion_requests: DataDeletionRequest[];
  terms_status: {
    needs_review: boolean;
    missing: string[];
  };
  data_retention_info: Array<{
    data_type: string;
    retention_days: number;
    action: string;
  }>;
}

export const privacyApi = {
  // Get privacy dashboard overview
  getDashboard: async (): Promise<PrivacyDashboard> => {
    const response = await apiClient.get('/privacy/dashboard');
    return response.data;
  },

  // Get consent preferences
  getConsents: async (): Promise<{ consents: ConsentPreferences; consent_types: Record<string, unknown> }> => {
    const response = await apiClient.get('/privacy/consents');
    return response.data;
  },

  // Update consent preferences
  updateConsents: async (consents: Partial<Record<string, boolean>>): Promise<{ consents: ConsentPreferences }> => {
    const response = await apiClient.put('/privacy/consents', consents);
    return response.data;
  },

  // Request data export
  requestExport: async (options?: {
    format?: 'json' | 'csv' | 'zip';
    export_type?: 'full' | 'partial';
    include_data_types?: string[];
  }): Promise<DataExportRequest> => {
    const response = await apiClient.post('/privacy/export', options);
    return response.data.request;
  },

  // Get export requests
  getExportRequests: async (): Promise<DataExportRequest[]> => {
    const response = await apiClient.get('/privacy/exports');
    return response.data.requests;
  },

  // Download export
  downloadExport: async (id: string, token: string): Promise<Blob> => {
    const response = await apiClient.get(`/privacy/exports/${id}/download?token=${token}`, {
      responseType: 'blob',
    });
    return response.data;
  },

  // Request data deletion
  requestDeletion: async (options?: {
    deletion_type?: 'full' | 'partial' | 'anonymize';
    reason?: string;
    data_types_to_delete?: string[];
  }): Promise<DataDeletionRequest> => {
    const response = await apiClient.post('/privacy/deletion', options);
    return response.data.request;
  },

  // Get deletion request status
  getDeletionStatus: async (): Promise<DataDeletionRequest | null> => {
    const response = await apiClient.get('/privacy/deletion');
    return response.data.request;
  },

  // Cancel deletion request
  cancelDeletion: async (id: string, reason?: string): Promise<DataDeletionRequest> => {
    const response = await apiClient.delete(`/privacy/deletion/${id}`, {
      data: { reason },
    });
    return response.data.request;
  },

  // Get terms acceptance status
  getTermsStatus: async (): Promise<{
    current_versions: Record<string, string>;
    accepted: TermsAcceptance[];
    missing: string[];
  }> => {
    const response = await apiClient.get('/privacy/terms');
    return response.data;
  },

  // Accept terms
  acceptTerms: async (documentType: string, version?: string): Promise<unknown> => {
    const response = await apiClient.post(`/privacy/terms/${documentType}/accept`, { version });
    return response.data;
  },

  // Get cookie preferences
  getCookiePreferences: async (): Promise<CookiePreferences> => {
    const response = await apiClient.get('/privacy/cookies');
    return response.data.preferences;
  },

  // Update cookie preferences
  updateCookiePreferences: async (preferences: Partial<CookiePreferences>): Promise<CookiePreferences> => {
    const response = await apiClient.put('/privacy/cookies', preferences);
    return response.data.preferences;
  },
};

export default privacyApi;
