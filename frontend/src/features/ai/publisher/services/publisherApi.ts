import api from '@/shared/api/api';
import type {
  Publisher,
  PublisherDashboardStats,
  PublisherAnalytics,
  PublisherEarnings,
  TemplateSummary,
  Transaction,
  PayoutRequest,
  StripeSetupRequest,
  StripeSetupResponse,
  StripeStatusResponse,
  PaginationMeta,
} from '../types';

const BASE_URL = '/api/v1/ai/publisher';

export interface PublishersResponse {
  data: Publisher[];
  meta: PaginationMeta;
}

export interface TemplatesResponse {
  data: TemplateSummary[];
  meta: PaginationMeta;
}

export interface PayoutsResponse {
  data: Transaction[];
  meta: PaginationMeta;
}

// Get list of publishers (admin)
export const getPublishers = async (params?: {
  status?: string;
  page?: number;
  per_page?: number;
}): Promise<PublishersResponse> => {
  const response = await api.get(BASE_URL, { params });
  return response.data;
};

// Get current user's publisher profile
export const getMyPublisher = async (): Promise<{ data: Publisher }> => {
  const response = await api.get(`${BASE_URL}/me`);
  return response.data;
};

// Get publisher by ID
export const getPublisher = async (id: string): Promise<{ data: Publisher }> => {
  const response = await api.get(`${BASE_URL}/${id}`);
  return response.data;
};

// Create publisher profile
export const createPublisher = async (data: {
  publisher_name: string;
  publisher_slug: string;
  description?: string;
  website_url?: string;
  support_email?: string;
  branding?: Record<string, unknown>;
}): Promise<{ data: Publisher; message: string }> => {
  const response = await api.post(BASE_URL, data);
  return response.data;
};

// Get publisher dashboard stats
export const getPublisherDashboard = async (
  id: string
): Promise<{ data: PublisherDashboardStats }> => {
  const response = await api.get(`${BASE_URL}/${id}/dashboard`);
  return response.data;
};

// Get publisher analytics
export const getPublisherAnalytics = async (
  id: string,
  params?: { period?: number }
): Promise<{ data: PublisherAnalytics }> => {
  const response = await api.get(`${BASE_URL}/${id}/analytics`, { params });
  return response.data;
};

// Get publisher earnings
export const getPublisherEarnings = async (
  id: string
): Promise<{ data: PublisherEarnings }> => {
  const response = await api.get(`${BASE_URL}/${id}/earnings`);
  return response.data;
};

// Get publisher's templates
export const getPublisherTemplates = async (
  id: string,
  params?: { status?: string; page?: number; per_page?: number }
): Promise<TemplatesResponse> => {
  const response = await api.get(`${BASE_URL}/${id}/templates`, { params });
  return response.data;
};

// Get publisher payouts
export const getPublisherPayouts = async (
  id: string,
  params?: { page?: number; per_page?: number }
): Promise<PayoutsResponse> => {
  const response = await api.get(`${BASE_URL}/${id}/payouts`, { params });
  return response.data;
};

// Request payout
export const requestPayout = async (
  id: string,
  data: PayoutRequest
): Promise<{ data: { transfer_id: string; amount: number }; message: string }> => {
  const response = await api.post(`${BASE_URL}/${id}/request_payout`, data);
  return response.data;
};

// Setup Stripe Connect
export const setupStripeConnect = async (
  id: string,
  data: StripeSetupRequest
): Promise<{ data: StripeSetupResponse }> => {
  const response = await api.post(`${BASE_URL}/${id}/stripe_setup`, data);
  return response.data;
};

// Get Stripe account status
export const getStripeStatus = async (
  id: string
): Promise<{ data: StripeStatusResponse }> => {
  const response = await api.get(`${BASE_URL}/${id}/stripe_status`);
  return response.data;
};

export default {
  getPublishers,
  getMyPublisher,
  getPublisher,
  createPublisher,
  getPublisherDashboard,
  getPublisherAnalytics,
  getPublisherEarnings,
  getPublisherTemplates,
  getPublisherPayouts,
  requestPayout,
  setupStripeConnect,
  getStripeStatus,
};
