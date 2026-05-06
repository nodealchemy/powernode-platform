import { api } from '@/shared/services/api';

export interface WaitlistSignupRequest {
  email: string;
  source?: string;
  utm_source?: string;
  utm_medium?: string;
  utm_campaign?: string;
  utm_term?: string;
  utm_content?: string;
}

export interface WaitlistSignupResponse {
  data: {
    id?: string;
    email?: string;
    status?: string;
    already_subscribed?: boolean;
  };
  message?: string;
}

class LeadsApi {
  /**
   * Submit a waitlist signup. Idempotent: re-submitting the same email returns
   * { already_subscribed: true } without leaking the prior signup timestamp.
   */
  async submitWaitlist(payload: WaitlistSignupRequest): Promise<WaitlistSignupResponse> {
    const response = await api.post('/marketing/public/leads/waitlist', payload);
    return response.data;
  }
}

export const leadsApi = new LeadsApi();
