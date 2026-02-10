# frozen_string_literal: true

class CreateRevenueIntelligenceSystem < ActiveRecord::Migration[8.0]
  def change
    # Customer Health Scores - Track customer health metrics
    create_table :customer_health_scores, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :subscription, type: :uuid, foreign_key: true, index: true

      # Overall health score (0-100)
      t.decimal :overall_score, precision: 5, scale: 2, null: false
      t.string :health_status, null: false, default: "healthy"

      # Component scores (0-100)
      t.decimal :engagement_score, precision: 5, scale: 2
      t.decimal :payment_score, precision: 5, scale: 2
      t.decimal :usage_score, precision: 5, scale: 2
      t.decimal :support_score, precision: 5, scale: 2
      t.decimal :tenure_score, precision: 5, scale: 2

      # Risk indicators
      t.boolean :at_risk, default: false
      t.string :risk_level, default: "low"
      t.text :risk_factors, array: true, default: []

      # Trend data
      t.decimal :score_change_30d, precision: 5, scale: 2
      t.decimal :score_change_90d, precision: 5, scale: 2
      t.string :trend_direction, default: "stable"

      # Raw metrics used for scoring
      t.jsonb :metrics_snapshot, default: {}
      t.jsonb :component_details, default: {}

      t.datetime :calculated_at, null: false
      t.timestamps

      t.index :overall_score
      t.index :health_status
      t.index :at_risk
      t.index :calculated_at
      t.check_constraint "health_status IN ('critical', 'at_risk', 'needs_attention', 'healthy', 'thriving')", name: "customer_health_scores_status_check"
      t.check_constraint "risk_level IN ('critical', 'high', 'medium', 'low', 'none')", name: "customer_health_scores_risk_level_check"
      t.check_constraint "trend_direction IN ('improving', 'stable', 'declining', 'critical_decline')", name: "customer_health_scores_trend_check"
    end

    # Churn Predictions - ML-based churn probability
    create_table :churn_predictions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :subscription, type: :uuid, foreign_key: true, index: true

      # Prediction results
      t.decimal :churn_probability, precision: 5, scale: 4, null: false
      t.string :risk_tier, null: false
      t.date :predicted_churn_date
      t.integer :days_until_churn

      # Contributing factors
      t.jsonb :contributing_factors, default: []
      t.string :primary_risk_factor
      t.decimal :confidence_score, precision: 5, scale: 4

      # Model metadata
      t.string :model_version, null: false
      t.string :prediction_type, default: "monthly"

      # Intervention recommendations
      t.jsonb :recommended_actions, default: []
      t.boolean :intervention_triggered, default: false
      t.datetime :intervention_at

      t.datetime :predicted_at, null: false
      t.timestamps

      t.index :churn_probability
      t.index :risk_tier
      t.index :predicted_at
      t.check_constraint "risk_tier IN ('critical', 'high', 'medium', 'low', 'minimal')", name: "churn_predictions_risk_tier_check"
      t.check_constraint "prediction_type IN ('weekly', 'monthly', 'quarterly')", name: "churn_predictions_type_check"
    end

    # Revenue Forecasts - Projected revenue metrics
    create_table :revenue_forecasts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, foreign_key: true, index: true

      # Forecast period
      t.date :forecast_date, null: false
      t.string :forecast_type, null: false
      t.string :forecast_period, null: false

      # Projected values
      t.decimal :projected_mrr, precision: 15, scale: 2
      t.decimal :projected_arr, precision: 15, scale: 2
      t.decimal :projected_new_revenue, precision: 15, scale: 2
      t.decimal :projected_expansion_revenue, precision: 15, scale: 2
      t.decimal :projected_churned_revenue, precision: 15, scale: 2
      t.decimal :projected_net_revenue, precision: 15, scale: 2

      # Customer projections
      t.integer :projected_new_customers
      t.integer :projected_churned_customers
      t.integer :projected_total_customers

      # Confidence intervals
      t.decimal :lower_bound, precision: 15, scale: 2
      t.decimal :upper_bound, precision: 15, scale: 2
      t.decimal :confidence_level, precision: 5, scale: 2, default: 95.0

      # Model metadata
      t.string :model_version
      t.jsonb :assumptions, default: {}
      t.jsonb :contributing_factors, default: []

      # Actual values (filled in after period ends)
      t.decimal :actual_mrr, precision: 15, scale: 2
      t.decimal :accuracy_percentage, precision: 5, scale: 2

      t.datetime :generated_at, null: false
      t.timestamps

      t.index [ :forecast_date, :forecast_type ]
      t.index :forecast_period
      t.check_constraint "forecast_type IN ('mrr', 'arr', 'customers', 'revenue')", name: "revenue_forecasts_type_check"
      t.check_constraint "forecast_period IN ('weekly', 'monthly', 'quarterly', 'yearly')", name: "revenue_forecasts_period_check"
    end

    # Analytics Alerts - Threshold-based alerting
    create_table :analytics_alerts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, foreign_key: true, index: true

      # Alert configuration
      t.string :name, null: false
      t.string :alert_type, null: false
      t.string :metric_name, null: false
      t.string :condition, null: false
      t.decimal :threshold_value, precision: 15, scale: 4, null: false
      t.string :comparison_period, default: "previous_period"

      # Alert status
      t.string :status, null: false, default: "enabled"
      t.datetime :last_triggered_at
      t.integer :trigger_count, default: 0

      # Current value tracking
      t.decimal :current_value, precision: 15, scale: 4
      t.datetime :last_checked_at

      # Notification settings
      t.text :notification_channels, array: true, default: []
      t.jsonb :notification_settings, default: {}
      t.boolean :auto_resolve, default: true

      # Cooldown to prevent alert spam
      t.integer :cooldown_minutes, default: 60
      t.datetime :cooldown_until

      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :alert_type
      t.index :status
      t.index :metric_name
      t.check_constraint "alert_type IN ('threshold', 'anomaly', 'trend', 'comparison')", name: "analytics_alerts_type_check"
      t.check_constraint "condition IN ('greater_than', 'less_than', 'equals', 'change_percent', 'anomaly_detected')", name: "analytics_alerts_condition_check"
      t.check_constraint "status IN ('enabled', 'disabled', 'triggered', 'resolved')", name: "analytics_alerts_status_check"
    end

    # Alert Events - Historical record of triggered alerts
    create_table :analytics_alert_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :analytics_alert, type: :uuid, null: false, foreign_key: true, index: true
      t.references :account, type: :uuid, foreign_key: true, index: true

      t.string :event_type, null: false
      t.decimal :triggered_value, precision: 15, scale: 4
      t.decimal :threshold_value, precision: 15, scale: 4
      t.text :message
      t.string :severity, default: "medium"

      t.boolean :acknowledged, default: false
      t.datetime :acknowledged_at
      t.string :acknowledged_by

      t.boolean :resolved, default: false
      t.datetime :resolved_at
      t.string :resolution_notes

      t.jsonb :context, default: {}
      t.timestamps

      t.index :event_type
      t.index :severity
      t.index [ :analytics_alert_id, :created_at ]
      t.check_constraint "event_type IN ('triggered', 'resolved', 'acknowledged', 'escalated')", name: "alert_events_type_check"
      t.check_constraint "severity IN ('critical', 'high', 'medium', 'low', 'info')", name: "alert_events_severity_check"
    end
  end
end
