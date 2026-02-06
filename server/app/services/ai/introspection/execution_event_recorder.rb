# frozen_string_literal: true

module Ai
  module Introspection
    class ExecutionEventRecorder
      class << self
        def record(source:, event_type:, status:, metadata: {}, cost_usd: nil, duration_ms: nil, error: nil)
          account_id = resolve_account_id(source)
          return unless account_id

          attrs = {
            account_id: account_id,
            source_type: source.class.name,
            source_id: source.id,
            event_type: event_type,
            status: status,
            metadata: metadata,
            cost_usd: cost_usd,
            duration_ms: duration_ms
          }

          if error
            attrs[:error_class] = error.is_a?(Exception) ? error.class.name : error.to_s
            attrs[:error_message] = error.is_a?(Exception) ? error.message : nil
          end

          Ai::ExecutionEvent.create!(attrs)
        rescue => e
          Rails.logger.error "[ExecutionEventRecorder] Failed to record event: #{e.message}"
        end

        def record_async(source:, event_type:, status:, **options)
          # Use after_commit to avoid recording during failed transactions
          source_type = source.class.name
          source_id = source.id
          account_id = resolve_account_id(source)

          return unless account_id

          Thread.new do
            Ai::ExecutionEvent.create!(
              account_id: account_id,
              source_type: source_type,
              source_id: source_id,
              event_type: event_type,
              status: status,
              metadata: options[:metadata] || {},
              cost_usd: options[:cost_usd],
              duration_ms: options[:duration_ms],
              error_class: options[:error_class],
              error_message: options[:error_message]
            )
          rescue => e
            Rails.logger.error "[ExecutionEventRecorder] Async record failed: #{e.message}"
          end
        end

        private

        def resolve_account_id(source)
          if source.respond_to?(:account_id)
            source.account_id
          elsif source.respond_to?(:account)
            source.account&.id
          elsif source.respond_to?(:workflow) && source.workflow.respond_to?(:account_id)
            source.workflow.account_id
          elsif source.respond_to?(:pipeline) && source.pipeline.respond_to?(:account_id)
            source.pipeline.account_id
          end
        end
      end
    end
  end
end
