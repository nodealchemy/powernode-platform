import api from '@/shared/services/api';
import type {
  CustomerHealthScore,
  ChurnPrediction,
  RevenueForecast,
  AnalyticsAlert,
  AlertEvent,
  PredictiveAnalyticsSummary,
  AlertRecommendation,
  PaginationMeta,
} from '../types/predictive';

const BASE_URL = '/api/v1/predictive-analytics';

interface PaginatedResponse<T> {
  data: T[];
  meta: { pagination: PaginationMeta };
}

// ==================== Health Scores ====================

export const getHealthScores = async (params?: {
  account_id?: string;
  status?: string;
  at_risk?: boolean;
  page?: number;
  per_page?: number;
}): Promise<PaginatedResponse<CustomerHealthScore>> => {
  const response = await api.get(`${BASE_URL}/health_scores`, { params });
  return response.data;
};

export const getHealthScore = async (id: string): Promise<{ data: CustomerHealthScore }> => {
  const response = await api.get(`${BASE_URL}/health_scores/${id}`);
  return response.data;
};

export const calculateHealthScore = async (accountId?: string): Promise<{ data: CustomerHealthScore; message: string }> => {
  const response = await api.post(`${BASE_URL}/health_scores/calculate`, { account_id: accountId });
  return response.data;
};

// ==================== Churn Predictions ====================

export const getChurnPredictions = async (params?: {
  account_id?: string;
  risk_tier?: string;
  high_risk?: boolean;
  page?: number;
  per_page?: number;
}): Promise<PaginatedResponse<ChurnPrediction>> => {
  const response = await api.get(`${BASE_URL}/churn_predictions`, { params });
  return response.data;
};

export const getChurnPrediction = async (id: string): Promise<{ data: ChurnPrediction }> => {
  const response = await api.get(`${BASE_URL}/churn_predictions/${id}`);
  return response.data;
};

export const predictChurn = async (accountId?: string): Promise<{ data: ChurnPrediction; message: string }> => {
  const response = await api.post(`${BASE_URL}/churn_predictions/predict`, { account_id: accountId });
  return response.data;
};

// ==================== Revenue Forecasts ====================

export const getRevenueForecasts = async (params?: {
  account_id?: string;
  platform_wide?: boolean;
  period?: string;
  future_only?: boolean;
  page?: number;
  per_page?: number;
}): Promise<PaginatedResponse<RevenueForecast>> => {
  const response = await api.get(`${BASE_URL}/revenue_forecasts`, { params });
  return response.data;
};

export const generateForecast = async (params?: {
  account_id?: string;
  months_ahead?: number;
  period?: string;
}): Promise<{ data: RevenueForecast[]; message: string }> => {
  const response = await api.post(`${BASE_URL}/revenue_forecasts/generate`, params);
  return response.data;
};

// ==================== Alerts ====================

export const getAlerts = async (params?: {
  status?: string;
  metric?: string;
}): Promise<{ data: AnalyticsAlert[] }> => {
  const response = await api.get(`${BASE_URL}/alerts`, { params });
  return response.data;
};

export const getAlert = async (id: string): Promise<{ data: AnalyticsAlert }> => {
  const response = await api.get(`${BASE_URL}/alerts/${id}`);
  return response.data;
};

export const createAlert = async (data: {
  name: string;
  alert_type?: string;
  metric_name: string;
  condition: string;
  threshold_value: number;
  notification_channels?: string[];
  cooldown_minutes?: number;
  auto_resolve?: boolean;
}): Promise<{ data: AnalyticsAlert; message: string }> => {
  const response = await api.post(`${BASE_URL}/alerts`, data);
  return response.data;
};

export const updateAlert = async (id: string, data: Partial<AnalyticsAlert>): Promise<{ data: AnalyticsAlert }> => {
  const response = await api.patch(`${BASE_URL}/alerts/${id}`, data);
  return response.data;
};

export const deleteAlert = async (id: string): Promise<{ message: string }> => {
  const response = await api.delete(`${BASE_URL}/alerts/${id}`);
  return response.data;
};

export const getAlertEvents = async (alertId: string, params?: {
  unacknowledged?: boolean;
  page?: number;
  per_page?: number;
}): Promise<PaginatedResponse<AlertEvent>> => {
  const response = await api.get(`${BASE_URL}/alerts/${alertId}/events`, { params });
  return response.data;
};

export const acknowledgeAlert = async (id: string): Promise<{ message: string }> => {
  const response = await api.post(`${BASE_URL}/alerts/${id}/acknowledge`);
  return response.data;
};

// ==================== Summary & Recommendations ====================

export const getSummary = async (): Promise<{ data: PredictiveAnalyticsSummary }> => {
  const response = await api.get(`${BASE_URL}/summary`);
  return response.data;
};

export const getRecommendations = async (): Promise<{ data: AlertRecommendation[] }> => {
  const response = await api.get(`${BASE_URL}/recommendations`);
  return response.data;
};

export default {
  getHealthScores,
  getHealthScore,
  calculateHealthScore,
  getChurnPredictions,
  getChurnPrediction,
  predictChurn,
  getRevenueForecasts,
  generateForecast,
  getAlerts,
  getAlert,
  createAlert,
  updateAlert,
  deleteAlert,
  getAlertEvents,
  acknowledgeAlert,
  getSummary,
  getRecommendations,
};
