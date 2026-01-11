// Analytics page data types

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

export interface AnalyticsData {
  revenue: RevenueData;
  growth: GrowthData;
  churn: ChurnData;
  customers: CustomerData;
  cohorts: CohortData;
}
