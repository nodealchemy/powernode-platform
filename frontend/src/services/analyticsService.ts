import { api } from './api';

export interface AnalyticsResponse<T> {
  success: boolean;
  data: T;
  error?: string;
}

export interface RevenueData {
  current_metrics: {
    mrr: number;
    arr: number;
    active_subscriptions: number;
    total_customers: number;
    arpu: number;
    growth_rate: number;
  };
  historical_data: Array<{
    date: string;
    mrr: number;
    arr: number;
    active_subscriptions: number;
    new_subscriptions: number;
    churned_subscriptions: number;
  }>;
  period: {
    start_date: string;
    end_date: string;
  };
}

export interface GrowthData {
  compound_monthly_growth_rate: number;
  monthly_growth_data: Array<{
    date: string;
    mrr: number;
    growth_rate: number;
    new_revenue: number;
    churned_revenue: number;
  }>;
  forecasting: {
    next_month_projection: number;
    confidence_interval: string;
  };
  period: {
    start_date: string;
    end_date: string;
  };
}

export interface ChurnData {
  current_metrics: {
    customer_churn_rate: number;
    average_customer_churn_rate: number;
    average_revenue_churn_rate: number;
    customer_retention_rate: number;
  };
  churn_trend: Array<{
    date: string;
    customer_churn_rate: number;
    revenue_churn_rate: number;
    churned_customers: number;
    churned_subscriptions: number;
  }>;
  insights: {
    churn_risk_level: 'low' | 'medium' | 'high';
    recommended_actions: string[];
  };
  period: {
    start_date: string;
    end_date: string;
  };
}

export interface CustomerData {
  current_metrics: {
    total_customers: number;
    arpu: number;
    ltv: number;
    ltv_to_cac_ratio: number;
  };
  customer_growth_trend: Array<{
    date: string;
    total_customers: number;
    new_customers: number;
    churned_customers: number;
    net_growth: number;
    arpu: number;
    ltv: number;
  }>;
  segmentation: {
    by_plan: Array<{
      plan: string;
      customers: number;
    }>;
    by_tenure: Array<{
      segment: string;
      customers: number;
    }>;
  };
  period: {
    start_date: string;
    end_date: string;
  };
}

export interface CohortData {
  cohorts: Array<{
    cohort_date: string;
    cohort_size: number;
    retention_rates: Array<{
      month: number;
      retention_rate: number;
      retained_customers: number;
    }>;
  }>;
  summary: {
    total_cohorts: number;
    average_first_month_retention: number;
    average_six_month_retention: number;
  };
}

class AnalyticsService {
  
  async getRevenueAnalytics(
    startDate: string, 
    endDate: string, 
    accountId?: string
  ): Promise<AnalyticsResponse<RevenueData>> {
    const params = new URLSearchParams({
      start_date: startDate,
      end_date: endDate,
      ...(accountId && { account_id: accountId })
    });

    const response = await api.get(`/analytics/revenue?${params}`);
    return response.data;
  }

  async getGrowthAnalytics(
    startDate: string, 
    endDate: string, 
    accountId?: string
  ): Promise<AnalyticsResponse<GrowthData>> {
    const params = new URLSearchParams({
      start_date: startDate,
      end_date: endDate,
      ...(accountId && { account_id: accountId })
    });

    const response = await api.get(`/analytics/growth?${params}`);
    return response.data;
  }

  async getChurnAnalytics(
    startDate: string, 
    endDate: string, 
    accountId?: string
  ): Promise<AnalyticsResponse<ChurnData>> {
    const params = new URLSearchParams({
      start_date: startDate,
      end_date: endDate,
      ...(accountId && { account_id: accountId })
    });

    const response = await api.get(`/analytics/churn?${params}`);
    return response.data;
  }

  async getCustomerAnalytics(
    startDate: string, 
    endDate: string, 
    accountId?: string
  ): Promise<AnalyticsResponse<CustomerData>> {
    const params = new URLSearchParams({
      start_date: startDate,
      end_date: endDate,
      ...(accountId && { account_id: accountId })
    });

    const response = await api.get(`/analytics/customers?${params}`);
    return response.data;
  }

  async getCohortAnalytics(accountId?: string): Promise<AnalyticsResponse<CohortData>> {
    const params = new URLSearchParams({
      ...(accountId && { account_id: accountId })
    });

    const response = await api.get(`/analytics/cohorts?${params}`);
    return response.data;
  }

  async exportAnalytics(
    format: 'csv' | 'pdf',
    reportType: string,
    dateRange: { startDate: Date; endDate: Date },
    accountId?: string
  ): Promise<void> {
    const params = new URLSearchParams({
      format,
      report_type: reportType,
      start_date: dateRange.startDate.toISOString().split('T')[0],
      end_date: dateRange.endDate.toISOString().split('T')[0],
      ...(accountId && { account_id: accountId })
    });

    const response = await api.get(`/analytics/export?${params}`, {
      responseType: 'blob'
    });

    // Create and trigger download
    const blob = new Blob([response.data]);
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${reportType}_analytics_${new Date().toISOString().split('T')[0]}.${format}`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    window.URL.revokeObjectURL(url);
  }

  // Real-time analytics updates via WebSocket
  subscribeToAnalyticsUpdates(callback: (data: any) => void) {
    // This would integrate with the WebSocket connection
    // For now, we'll use polling as fallback
    return setInterval(async () => {
      try {
        const endDate = new Date().toISOString().split('T')[0];
        const startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
        
        const revenue = await this.getRevenueAnalytics(startDate, endDate);
        callback({
          type: 'revenue_update',
          data: revenue.data.current_metrics
        });
      } catch (error) {
        console.error('Failed to fetch real-time analytics:', error);
      }
    }, 30000); // Update every 30 seconds
  }

  unsubscribeFromAnalyticsUpdates(intervalId: number) {
    clearInterval(intervalId);
  }
}

export const analyticsService = new AnalyticsService();