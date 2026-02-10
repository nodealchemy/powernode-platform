# frozen_string_literal: true

module Ai
  module Concerns
    module AccountScoped
      extend ActiveSupport::Concern

      included do
        attr_reader :account
      end

      def initialize(account:)
        @account = account
      end

      private

      def success_response(data = {}, message: nil)
        response = { success: true }
        response[:message] = message if message
        response.merge(data)
      end

      def error_response(message, details: nil, code: nil)
        response = { success: false, error: message }
        response[:details] = details if details
        response[:code] = code if code
        response
      end

      def audit_action(action:, resource_type: nil, resource_id: nil, details: {})
        Ai::ComplianceAuditEntry.create(
          account: @account,
          action_type: action,
          resource_type: resource_type,
          resource_id: resource_id,
          description: details[:description] || action,
          outcome: details[:outcome] || "success",
          context: details.except(:description, :outcome)
        )
      rescue StandardError => e
        Rails.logger.error "[AccountScoped] Failed to create audit entry: #{e.message}"
      end
    end
  end
end
