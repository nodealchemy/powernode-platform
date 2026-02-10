// Predictive Analytics Types

export interface CustomerHealthScore {
  id: string;
  account_id: string;
  overall_score: number;
  health_status: 'critical' | 'at_risk' | 'needs_attention' | 'healthy' | 'thriving';
  at_risk: boolean;
  risk_level: 'critical' | 'high' | 'medium' | 'low' | 'none';
  risk_factors: string[];
  trend_direction: 'improving' | 'stable' | 'declining' | 'critical_decline';
  score_change_30d: number | null;
  components: {
    engagement: number | null;
    payment: number | null;
    usage: number | null;
    support: number | null;
    tenure: number | null;
  };
  calculated_at: string;
}

export interface ChurnPrediction {
  id: string;
  account_id: string;
  churn_probability: number;
  probability_percentage: number;
  risk_tier: 'critical' | 'high' | 'medium' | 'low' | 'minimal';
  predicted_churn_date: string | null;
  days_until_churn: number | null;
  primary_risk_factor: string | null;
  confidence_score: number | null;
  recommended_actions: RecommendedAction[];
  intervention_triggered: boolean;
  predicted_at: string;
  contributing_factors?: ContributingFactor[];
}

export interface ContributingFactor {
  factor: string;
  weight: number;
  description: string;
  value: number | string | boolean;
}

export interface RecommendedAction {
  action: string;
  priority: 'high' | 'medium' | 'low';
  description: string;
  triggered_by?: string;
  factor_description?: string;
}

export interface RevenueForecast {
  id: string;
  forecast_date: string;
  forecast_type: 'mrr' | 'arr' | 'customers' | 'revenue';
  forecast_period: 'weekly' | 'monthly' | 'quarterly' | 'yearly';
  projections: {
    mrr: number;
    arr: number;
    new_revenue: number;
    expansion_revenue: number;
    churned_revenue: number;
    net_revenue: number;
  };
  customers: {
    projected_new: number;
    projected_churned: number;
    projected_total: number;
  };
  confidence: {
    level: number;
    lower_bound: number;
    upper_bound: number;
  };
  actuals: {
    mrr: number;
    accuracy: number;
    variance: number;
    variance_percentage: number;
  } | null;
  generated_at: string;
}

export interface AnalyticsAlert {
  id: string;
  name: string;
  alert_type: 'threshold' | 'anomaly' | 'trend' | 'comparison';
  metric_name: string;
  condition: 'greater_than' | 'less_than' | 'equals' | 'change_percent' | 'anomaly_detected';
  threshold_value: number;
  current_value: number | null;
  status: 'enabled' | 'disabled' | 'triggered' | 'resolved';
  last_triggered_at: string | null;
  trigger_count: number;
  notification_channels: string[];
  in_cooldown: boolean;
}

export interface AlertEvent {
  id: string;
  alert_id: string;
  event_type: 'triggered' | 'resolved' | 'acknowledged' | 'escalated';
  triggered_value: number | null;
  threshold_value: number | null;
  message: string;
  severity: 'critical' | 'high' | 'medium' | 'low' | 'info';
  acknowledged: boolean;
  resolved: boolean;
  created_at: string;
}

export interface PredictiveAnalyticsSummary {
  health_scores: {
    at_risk_count: number;
    healthy_count: number;
    average_score: number | null;
  };
  churn_predictions: {
    high_risk_count: number;
    needs_intervention: number;
    average_probability: number | null;
  };
  alerts: {
    total_alerts: number;
    enabled: number;
    triggered: number;
    unacknowledged: number;
    recent_events: AlertEvent[];
    by_metric: Record<string, number>;
  };
  last_updated: string;
}

export interface AlertRecommendation {
  name: string;
  metric_name: string;
  condition: string;
  threshold_value: number;
  description: string;
}

export interface PaginationMeta {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}
