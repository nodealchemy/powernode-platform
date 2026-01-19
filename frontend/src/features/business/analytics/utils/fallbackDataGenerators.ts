import type { RevenueData, GrowthData, ChurnData, CustomerData, CohortData } from '../types/analyticsTypes';

/**
 * Generate fallback revenue data for demo purposes
 */
export const generateFallbackRevenueData = (startDate: string, endDate: string): RevenueData => {
  const data = [];
  const start = new Date(startDate);
  const end = new Date(endDate);

  let currentDate = new Date(start);
  let baseMRR = 5000;

  while (currentDate <= end) {
    const growth = 1 + (Math.random() * 0.2 - 0.1);
    baseMRR *= growth;

    data.push({
      date: currentDate.toISOString().split('T')[0],
      mrr: Math.round(baseMRR),
      arr: Math.round(baseMRR * 12),
      active_subscriptions: Math.round(baseMRR / 50),
      new_subscriptions: Math.round(Math.random() * 10),
      churned_subscriptions: Math.round(Math.random() * 5)
    });

    currentDate.setMonth(currentDate.getMonth() + 1);
  }

  return {
    current_metrics: {
      mrr: baseMRR,
      arr: baseMRR * 12,
      active_subscriptions: Math.round(baseMRR / 50),
      total_customers: Math.round(baseMRR / 50),
      arpu: 50,
      growth_rate: 15.5
    },
    historical_data: data,
    period: { start_date: startDate, end_date: endDate }
  };
};

/**
 * Generate fallback growth data for demo purposes
 */
export const generateFallbackGrowthData = (startDate: string, endDate: string): GrowthData => {
  const data = [];
  const start = new Date(startDate);
  const end = new Date(endDate);

  let currentDate = new Date(start);
  let baseMRR = 5000;

  while (currentDate <= end) {
    const growthRate = (Math.random() * 20 - 5);
    baseMRR *= (1 + growthRate / 100);

    data.push({
      date: currentDate.toISOString().split('T')[0],
      mrr: Math.round(baseMRR),
      growth_rate: Math.round(growthRate * 10) / 10,
      new_revenue: Math.round(baseMRR * 0.1),
      churned_revenue: Math.round(baseMRR * 0.05)
    });

    currentDate.setMonth(currentDate.getMonth() + 1);
  }

  return {
    compound_monthly_growth_rate: 8.5,
    monthly_growth_data: data,
    forecasting: {
      next_month_projection: Math.round(baseMRR * 1.1),
      confidence_interval: '±15%'
    },
    period: { start_date: startDate, end_date: endDate }
  };
};

/**
 * Generate fallback churn data for demo purposes
 */
export const generateFallbackChurnData = (startDate: string, endDate: string): ChurnData => {
  const data = [];
  const start = new Date(startDate);
  const end = new Date(endDate);

  let currentDate = new Date(start);

  while (currentDate <= end) {
    data.push({
      date: currentDate.toISOString().split('T')[0],
      customer_churn_rate: Math.random() * 8,
      revenue_churn_rate: Math.random() * 6,
      churned_customers: Math.round(Math.random() * 15),
      churned_subscriptions: Math.round(Math.random() * 10)
    });

    currentDate.setMonth(currentDate.getMonth() + 1);
  }

  return {
    current_metrics: {
      customer_churn_rate: 3.2,
      average_customer_churn_rate: 4.1,
      average_revenue_churn_rate: 2.8,
      customer_retention_rate: 96.8
    },
    churn_trend: data,
    insights: {
      churn_risk_level: 'medium' as const,
      recommended_actions: [
        'Implement proactive customer success outreach',
        'Analyze churned customer feedback',
        'Consider loyalty programs'
      ]
    },
    period: { start_date: startDate, end_date: endDate }
  };
};

/**
 * Generate fallback customer data for demo purposes
 */
export const generateFallbackCustomerData = (startDate: string, endDate: string): CustomerData => {
  const data = [];
  const start = new Date(startDate);
  const end = new Date(endDate);

  let currentDate = new Date(start);
  let totalCustomers = 100;

  while (currentDate <= end) {
    const newCustomers = Math.round(Math.random() * 20);
    const churnedCustomers = Math.round(Math.random() * 8);
    totalCustomers += (newCustomers - churnedCustomers);

    data.push({
      date: currentDate.toISOString().split('T')[0],
      total_customers: totalCustomers,
      new_customers: newCustomers,
      churned_customers: churnedCustomers,
      net_growth: newCustomers - churnedCustomers,
      arpu: Math.round((40 + Math.random() * 30) * 100) / 100,
      ltv: Math.round((800 + Math.random() * 600) * 100) / 100
    });

    currentDate.setMonth(currentDate.getMonth() + 1);
  }

  return {
    current_metrics: {
      total_customers: totalCustomers,
      arpu: 55.50,
      ltv: 1100.00,
      ltv_to_cac_ratio: 3.2
    },
    customer_growth_trend: data,
    segmentation: {
      by_plan: [
        { plan: 'Starter', customers: Math.round(totalCustomers * 0.6) },
        { plan: 'Professional', customers: Math.round(totalCustomers * 0.3) },
        { plan: 'Enterprise', customers: Math.round(totalCustomers * 0.1) }
      ],
      by_tenure: [
        { segment: 'New (0-3 months)', customers: Math.round(totalCustomers * 0.25) },
        { segment: 'Growing (3-12 months)', customers: Math.round(totalCustomers * 0.45) },
        { segment: 'Mature (12+ months)', customers: Math.round(totalCustomers * 0.30) }
      ]
    },
    period: { start_date: startDate, end_date: endDate }
  };
};

/**
 * Generate fallback cohort data for demo purposes
 */
export const generateFallbackCohortData = (): CohortData => {
  const cohorts = [];

  for (let i = 0; i < 12; i++) {
    const cohortDate = new Date();
    cohortDate.setMonth(cohortDate.getMonth() - i);
    const cohortSize = Math.round(20 + Math.random() * 40);

    const retentionRates = [];
    let retentionRate = 1.0;

    for (let month = 0; month < 12; month++) {
      if (month > 0) {
        retentionRate *= (0.85 + Math.random() * 0.10);
      }

      retentionRates.push({
        month,
        retention_rate: retentionRate,
        retained_customers: Math.round(cohortSize * retentionRate)
      });
    }

    cohorts.push({
      cohort_date: cohortDate.toISOString().slice(0, 7),
      cohort_size: cohortSize,
      retention_rates: retentionRates
    });
  }

  return {
    cohorts,
    summary: {
      total_cohorts: cohorts.length,
      average_first_month_retention: 92.5,
      average_six_month_retention: 68.8
    }
  };
};
