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

        # Returns per-action tool definitions keyed by external registry name.
        # Single-action tools inherit this default which strips the :action param.
        # Multi-action tools override to provide focused per-action schemas.
        def action_definitions
          defn = definition
          params = (defn[:parameters] || {}).except(:action)
          { defn[:name] => { description: defn[:description], parameters: params } }
        end

        def permitted?(agent:)
          return true unless self::REQUIRED_PERMISSION
          return true unless agent

          # Check if any user in the agent's account has the required permission.
          # Account doesn't have permissions directly — they're on User via roles.
          if agent.respond_to?(:account) && agent.account
            Permission.joins(roles: :user_roles)
                      .where(user_roles: { user_id: agent.account.users.select(:id) })
                      .where(name: self::REQUIRED_PERMISSION)
                      .exists?
          else
            true
          end
        rescue StandardError
          # If permission check fails, allow the tool — execution is already
          # gated by the triggering user's API-level authorization.
          true
        end

        def tool_name
          definition[:name]
        end
      end

      def initialize(account:, agent: nil, user: nil)
        @account = account
        @agent = agent
        @user = user
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

      attr_reader :account, :agent, :user
    end
  end
end
