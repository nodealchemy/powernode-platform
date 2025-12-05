# frozen_string_literal: true

# AI Workflow Event System Initializer
# This initializer sets up the event-driven trigger system for AI workflows

Rails.application.configure do
  # Initialize the event system after Rails has fully loaded
  config.after_initialize do
    # Only initialize in certain environments
    next unless Rails.env.development? || Rails.env.production?

    begin
      Rails.logger.info "Initializing AI Workflow Event System..."

      # Start the event dispatcher
      event_dispatcher = AiWorkflowEventDispatcherService.instance
      event_dispatcher.start_event_processor

      # Initialize the trigger service (this registers all event listeners)
      trigger_service = AiWorkflowTriggerService.instance

      # Initialize platform integration service
      integration_service = AiWorkflowEventIntegrationService.instance

      Rails.logger.info "✅ AI Workflow Event System initialized successfully"
      Rails.logger.info "🎯 Event Types Available: #{AiWorkflowEventDispatcherService::WORKFLOW_EVENTS.keys.size}"
      Rails.logger.info "🔄 Event Processor Status: #{event_dispatcher.health_status[:running] ? 'Running' : 'Stopped'}"

    rescue => e
      Rails.logger.error "❌ Failed to initialize AI Workflow Event System: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  # Gracefully shut down the event system when Rails shuts down
  config.before_configuration do
    at_exit do
      begin
        if defined?(AiWorkflowEventDispatcherService)
          event_dispatcher = AiWorkflowEventDispatcherService.instance
          event_dispatcher.stop_event_processor
          Rails.logger.info "AI Workflow Event System shut down gracefully"
        end
      rescue => e
        Rails.logger.error "Error shutting down AI Workflow Event System: #{e.message}"
      end
    end
  end
end

# Development/Test helpers
if Rails.env.development? || Rails.env.test?
  Rails.application.configure do
    # Add development helpers for testing the event system
    config.after_initialize do
      # Define helper methods for testing events in development
      module AiWorkflowEventHelpers
        def self.dispatch_test_event(event_type, data = {})
          AiWorkflowEventDispatcherService.instance.dispatch_event(
            event_type,
            data.merge({ test: true, generated_at: Time.current.iso8601 }),
            { source: 'development_console' }
          )
        end

        def self.system_status
          {
            dispatcher: AiWorkflowEventDispatcherService.instance.health_status,
            triggers: AiWorkflowTriggerService.instance.status
          }
        end

        def self.available_events
          AiWorkflowEventDispatcherService::WORKFLOW_EVENTS
        end
      end

      # Make helpers available in Rails console
      if defined?(Rails::Console)
        Rails.application.console do
          Rails.logger.info "\n🤖 AI Workflow Event System Helpers available:"
          Rails.logger.info "   AiWorkflowEventHelpers.dispatch_test_event('workflow.test', {data: 'test'})"
          Rails.logger.info "   AiWorkflowEventHelpers.system_status"
          Rails.logger.info "   AiWorkflowEventHelpers.available_events"
          Rails.logger.info ""
        end
      end
    end
  end
end

# Health check endpoint for monitoring
if Rails.env.production?
  Rails.application.routes.draw do
    namespace :api do
      namespace :v1 do
        namespace :admin do
          get 'ai_workflow_events/health', to: proc {
            begin
              status = AiWorkflowEventDispatcherService.instance.health_status
              trigger_status = AiWorkflowTriggerService.instance.status

              health_data = {
                status: 'healthy',
                event_dispatcher: status,
                trigger_service: trigger_status,
                checked_at: Time.current.iso8601
              }

              [200, { 'Content-Type' => 'application/json' }, [health_data.to_json]]
            rescue => e
              error_data = {
                status: 'unhealthy',
                error: e.message,
                checked_at: Time.current.iso8601
              }

              [500, { 'Content-Type' => 'application/json' }, [error_data.to_json]]
            end
          }
        end
      end
    end
  end
end