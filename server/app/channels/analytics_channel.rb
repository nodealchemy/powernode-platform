# frozen_string_literal: true

class AnalyticsChannel < ApplicationCable::Channel
  def subscribed
    account_id = params[:account_id]
    Rails.logger.info "AnalyticsChannel subscription attempt - User: #{current_user&.id}, Account: #{account_id}"

    if current_user && authorized_for_analytics?(account_id)
      if account_id
        stream_for_account_analytics(account_id)
      else
        stream_for_global_analytics if current_user.has_permission?('analytics.global')
      end

      Rails.logger.info "User #{current_user.id} subscribed to analytics for account #{account_id || 'global'}"

      # Send welcome message with current analytics snapshot
      transmit({
        type: "analytics_connection_established",
        message: "Connected to real-time analytics",
        timestamp: Time.current.iso8601
      })
    else
      Rails.logger.warn "Unauthorized analytics subscription attempt for account #{account_id} by user #{current_user&.id}"
      Rails.logger.warn "Auth details - Current user present: #{!!current_user}, Authorization result: #{authorized_for_analytics?(account_id)}"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "User #{current_user&.id} unsubscribed from analytics"
  end

  # Client can request specific analytics data
  def request_analytics(data = {})
    account_id = data["account_id"]

    unless authorized_for_analytics?(account_id)
      transmit({
        type: "error",
        message: "Unauthorized analytics request"
      })
      return
    end

    analytics_service = RevenueAnalyticsService.new(
      account: account_id ? Account.find(account_id) : nil
    )

    # Get current metrics
    current_metrics = {
      mrr: analytics_service.current_mrr,
      arr: analytics_service.current_mrr * 12,
      active_customers: analytics_service.count_active_customers,
      churn_rate: analytics_service.calculate_churn_rate
    }

    transmit({
      type: "analytics_update",
      data: {
        current_metrics: current_metrics,
        timestamp: Time.current.iso8601,
        account_id: account_id
      }
    })
  rescue => e
    Rails.logger.error "Analytics request failed: #{e.message}"
    transmit({
      type: "error",
      message: "Failed to fetch analytics data"
    })
  end

  private

  def authorized_for_analytics?(account_id)
    return false unless current_user

    if account_id.present?
      # User must have analytics permission for the specific account
      account = Account.find_by(id: account_id)
      return false unless account

      current_user.has_permission?('analytics.read') &&
        (current_user.account_id == account.id || current_user.has_permission?('analytics.global'))
    else
      # Global analytics - user must have global analytics permission
      current_user.has_permission?('analytics.global')
    end
  end

  def stream_for_account_analytics(account_id)
    stream_from "analytics_account_#{account_id}"
  end

  def stream_for_global_analytics
    stream_from "analytics_global"
  end
end
