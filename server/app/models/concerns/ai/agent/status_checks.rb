# frozen_string_literal: true

module Ai
  class Agent
    module StatusChecks
      extend ActiveSupport::Concern

      # Status query methods
      def active?
        status == "active"
      end

      def inactive?
        status == "inactive"
      end

      def archived?
        status == "archived"
      end

      def error?
        status == "error"
      end

      def paused?
        status == "paused"
      end

      def mcp_client?
        agent_type == "mcp_client"
      end

      # Update last execution timestamp
      def mark_executed!
        update!(last_executed_at: Time.current)
      end
    end
  end
end
