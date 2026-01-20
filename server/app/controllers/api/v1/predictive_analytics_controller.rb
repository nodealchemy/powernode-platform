# frozen_string_literal: true

module Api
  module V1
    class PredictiveAnalyticsController < ApplicationController
      before_action -> { require_permission("analytics.read") }
      before_action -> { require_permission("analytics.manage") }, only: [:create_alert, :update_alert, :delete_alert]

      # GET /api/v1/predictive_analytics/health_scores
      def health_scores
        scope = params[:account_id] ? CustomerHealthScore.where(account_id: params[:account_id]) : CustomerHealthScore.all

        if params[:status].present?
          scope = scope.where(health_status: params[:status])
        end

        if params[:at_risk].present?
          scope = scope.where(at_risk: params[:at_risk] == "true")
        end

        paginated = scope.order(calculated_at: :desc).page(params[:page] || 1).per([params[:per_page]&.to_i || 25, 100].min)

        render_success(
          paginated.map(&:summary),
          meta: pagination_meta(paginated)
        )
      end

      # GET /api/v1/predictive_analytics/health_scores/:id
      def health_score
        score = CustomerHealthScore.find(params[:id])
        render_success(data: score.summary.merge(component_details: score.component_details))
      rescue ActiveRecord::RecordNotFound
        render_error("Health score not found", status: :not_found)
      end

      # POST /api/v1/predictive_analytics/health_scores/calculate
      def calculate_health_score
        account = if params[:account_id]
                    Account.find(params[:account_id])
                  else
                    current_account
                  end

        service = Analytics::CustomerHealthScoreService.new(account)
        score = service.calculate_health_score

        render_success(data: score.summary, message: "Health score calculated")
      rescue ActiveRecord::RecordNotFound
        render_error("Account not found", status: :not_found)
      end

      # GET /api/v1/predictive_analytics/churn_predictions
      def churn_predictions
        scope = params[:account_id] ? ChurnPrediction.where(account_id: params[:account_id]) : ChurnPrediction.all

        if params[:risk_tier].present?
          scope = scope.where(risk_tier: params[:risk_tier])
        end

        if params[:high_risk].present?
          scope = scope.high_risk
        end

        paginated = scope.order(predicted_at: :desc).page(params[:page] || 1).per([params[:per_page]&.to_i || 25, 100].min)

        render_success(
          paginated.map(&:summary),
          meta: pagination_meta(paginated)
        )
      end

      # GET /api/v1/predictive_analytics/churn_predictions/:id
      def churn_prediction
        prediction = ChurnPrediction.find(params[:id])
        render_success(data: prediction.summary.merge(contributing_factors: prediction.contributing_factors))
      rescue ActiveRecord::RecordNotFound
        render_error("Prediction not found", status: :not_found)
      end

      # POST /api/v1/predictive_analytics/churn_predictions/predict
      def predict_churn
        account = if params[:account_id]
                    Account.find(params[:account_id])
                  else
                    current_account
                  end

        service = Analytics::ChurnPredictionService.new(account)
        prediction = service.predict

        render_success(data: prediction.summary, message: "Churn prediction generated")
      rescue ActiveRecord::RecordNotFound
        render_error("Account not found", status: :not_found)
      end

      # GET /api/v1/predictive_analytics/revenue_forecasts
      def revenue_forecasts
        scope = RevenueForecast.all
        scope = scope.for_account(params[:account_id]) if params[:account_id].present?
        scope = scope.platform_wide if params[:platform_wide] == "true"
        scope = scope.by_period(params[:period]) if params[:period].present?
        scope = scope.future if params[:future_only] == "true"

        paginated = scope.order(forecast_date: :asc).page(params[:page] || 1).per([params[:per_page]&.to_i || 25, 100].min)

        render_success(
          paginated.map(&:summary),
          meta: pagination_meta(paginated)
        )
      end

      # POST /api/v1/predictive_analytics/revenue_forecasts/generate
      def generate_forecast
        months_ahead = (params[:months_ahead] || 12).to_i
        period = params[:period]&.to_sym || :monthly

        service = if params[:account_id]
                    Analytics::RevenueForecasterService.new(Account.find(params[:account_id]))
                  else
                    Analytics::RevenueForecasterService.new(nil)
                  end

        forecasts = service.generate_forecast(months_ahead: months_ahead, period: period)

        render_success(
          data: forecasts.map(&:summary),
          message: "#{forecasts.size} forecasts generated"
        )
      rescue ActiveRecord::RecordNotFound
        render_error("Account not found", status: :not_found)
      end

      # GET /api/v1/predictive_analytics/alerts
      def alerts
        scope = current_account ? current_account.analytics_alerts : AnalyticsAlert.platform_wide

        if params[:status].present?
          scope = scope.where(status: params[:status])
        end

        if params[:metric].present?
          scope = scope.by_metric(params[:metric])
        end

        render_success(scope.map(&:summary))
      end

      # GET /api/v1/predictive_analytics/alerts/:id
      def alert
        alert = AnalyticsAlert.find(params[:id])
        render_success(data: alert.summary)
      rescue ActiveRecord::RecordNotFound
        render_error("Alert not found", status: :not_found)
      end

      # POST /api/v1/predictive_analytics/alerts
      def create_alert
        result = Analytics::AlertService.create_alert(
          alert_params.merge(account: current_account)
        )

        if result[:success]
          render_success(data: result[:alert].summary, message: "Alert created", status: :created)
        else
          render_error(result[:errors].join(", "))
        end
      end

      # PATCH /api/v1/predictive_analytics/alerts/:id
      def update_alert
        alert = AnalyticsAlert.find(params[:id])
        if alert.update(alert_params)
          render_success(data: alert.summary)
        else
          render_error(alert.errors.full_messages.join(", "))
        end
      rescue ActiveRecord::RecordNotFound
        render_error("Alert not found", status: :not_found)
      end

      # DELETE /api/v1/predictive_analytics/alerts/:id
      def delete_alert
        alert = AnalyticsAlert.find(params[:id])
        alert.destroy
        render_success(message: "Alert deleted")
      rescue ActiveRecord::RecordNotFound
        render_error("Alert not found", status: :not_found)
      end

      # GET /api/v1/predictive_analytics/alerts/:id/events
      def alert_events
        alert = AnalyticsAlert.find(params[:id])
        events = alert.alert_events.recent

        if params[:unacknowledged].present?
          events = events.unacknowledged
        end

        paginated = events.page(params[:page] || 1).per([params[:per_page]&.to_i || 25, 100].min)

        render_success(
          paginated.map(&:summary),
          meta: pagination_meta(paginated)
        )
      rescue ActiveRecord::RecordNotFound
        render_error("Alert not found", status: :not_found)
      end

      # POST /api/v1/predictive_analytics/alerts/:id/acknowledge
      def acknowledge_alert
        alert = AnalyticsAlert.find(params[:id])
        alert.acknowledge!(by: current_user.email)
        render_success(message: "Alert acknowledged")
      rescue ActiveRecord::RecordNotFound
        render_error("Alert not found", status: :not_found)
      end

      # GET /api/v1/predictive_analytics/summary
      def summary
        render_success(
          data: {
            health_scores: {
              at_risk_count: CustomerHealthScore.at_risk.select("DISTINCT account_id").count,
              healthy_count: CustomerHealthScore.healthy.select("DISTINCT account_id").count,
              average_score: CustomerHealthScore.average(:overall_score)&.round(1)
            },
            churn_predictions: {
              high_risk_count: ChurnPrediction.high_risk.select("DISTINCT account_id").count,
              needs_intervention: ChurnPrediction.needs_intervention.count,
              average_probability: ChurnPrediction.average(:churn_probability)&.round(3)
            },
            alerts: Analytics::AlertService.summary,
            last_updated: Time.current
          }
        )
      end

      # GET /api/v1/predictive_analytics/recommendations
      def recommendations
        render_success(
          data: Analytics::AlertService.recommend_alerts(current_account)
        )
      end

      private

      def alert_params
        params.permit(
          :name, :alert_type, :metric_name, :condition, :threshold_value,
          :comparison_period, :cooldown_minutes, :auto_resolve,
          notification_channels: [], notification_settings: {}, metadata: {}
        )
      end

      def pagination_meta(paginated)
        {
          pagination: {
            current_page: paginated.current_page,
            per_page: paginated.limit_value,
            total_pages: paginated.total_pages,
            total_count: paginated.total_count
          }
        }
      end
    end
  end
end
