# frozen_string_literal: true

module Ai
  module Intelligence
    class BaseIntelligenceService
      attr_reader :account

      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      protected

      def aggregate_by_period(scope, period:, column: :created_at)
        case period
        when "daily" then scope.group_by_day(column)
        when "weekly" then scope.group_by_week(column)
        when "monthly" then scope.group_by_month(column)
        else scope.group_by_day(column)
        end
      end

      def calculate_trend(current, previous)
        return 0.0 if previous.zero?
        ((current - previous).to_f / previous * 100).round(2)
      end

      def calculate_percentile(values, percentile)
        return nil if values.empty?
        sorted = values.sort
        k = (percentile / 100.0 * (sorted.length - 1)).round
        sorted[k]
      end

      def risk_score(factors)
        return 0.0 if factors.empty?
        weighted_sum = factors.sum { |f| f[:weight] * f[:score] }
        total_weight = factors.sum { |f| f[:weight] }
        total_weight.positive? ? (weighted_sum / total_weight).round(2) : 0.0
      end

      def success_response(**data)
        { success: true }.merge(data)
      end

      def error_response(method_name, exception)
        @logger.error("[#{self.class.name}##{method_name}] #{exception.message}")
        @logger.error(exception.backtrace&.first(5)&.join("\n"))
        { success: false, error: exception.message }
      end

      def error_hash(message)
        { success: false, error: message }
      end

      def audit_action(action, resource_type, resource_id = nil, context: {})
        return unless defined?(PowernodeBusiness::Engine)

        attrs = {
          account: @account,
          action_type: "ai_intelligence_#{action}",
          resource_type: resource_type,
          outcome: "success",
          description: "AI Intelligence: #{action.humanize}",
          context: context
        }
        attrs[:resource_id] = resource_id if resource_id
        Ai::ComplianceAuditEntry.log!(**attrs)
      rescue StandardError => e
        @logger.warn("[#{self.class.name}] Audit log failed for #{action}: #{e.message}")
      end
    end
  end
end
