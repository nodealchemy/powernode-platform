# frozen_string_literal: true

module Ai
  module Tools
    class BaseTool
      REQUIRED_PERMISSION = nil
      MAX_CALLS_PER_EXECUTION = 20

      class << self
        def definition
          raise NotImplementedError, "#{name} must implement .definition"
        end

        def permitted?(agent:)
          return true unless self::REQUIRED_PERMISSION
          return true unless agent

          if agent.respond_to?(:account) && agent.account
            agent.account.permissions.exists?(name: self::REQUIRED_PERMISSION)
          else
            true
          end
        end

        def tool_name
          definition[:name]
        end
      end

      def initialize(account:, agent: nil)
        @account = account
        @agent = agent
      end

      def execute(params:)
        validate_params!(params)
        enforce_guardrails!
        call(params)
      end

      protected

      def call(params)
        raise NotImplementedError, "#{self.class.name} must implement #call"
      end

      def validate_params!(params)
        required = self.class.definition.dig(:parameters)&.select { |_, v| v[:required] }&.keys || []
        missing = required.select { |k| params[k].blank? }
        raise ArgumentError, "Missing required parameters: #{missing.join(', ')}" if missing.any?
      end

      def enforce_guardrails!
        validate_account_context!
      end

      def validate_account_context!
        return unless account

        unless account.is_a?(Account) && account.persisted?
          raise ArgumentError, "Invalid account context for tool execution"
        end
      end

      private

      attr_reader :account, :agent
    end
  end
end
