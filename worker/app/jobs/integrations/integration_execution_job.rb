# frozen_string_literal: true

module Integrations
  class IntegrationExecutionJob < BaseJob
    sidekiq_options queue: 'integrations',
                    retry: 3,
                    dead: true

    # Execute an integration asynchronously
    def execute(execution_id, input = {}, context = {})
      log_info("Starting integration execution", execution_id: execution_id)

      # Mark execution as running
      update_execution_status(execution_id, "running")

      # Fetch execution details
      execution = fetch_execution(execution_id)
      return unless execution

      instance_id = execution[:integration_instance_id]

      # Execute the integration
      result = execute_integration(instance_id, input, context)

      if result[:success]
        complete_execution(execution_id, result)
        log_info("Integration execution completed", execution_id: execution_id)
      else
        fail_execution(execution_id, result[:error])
        log_error("Integration execution failed", execution_id: execution_id, error: result[:error])
      end

      result
    rescue StandardError => e
      fail_execution(execution_id, e.message)
      log_error("Integration execution error", exception: e, execution_id: execution_id)
      raise
    end

    private

    def fetch_execution(execution_id)
      response = api_client.get("/api/v1/integrations/executions/#{execution_id}")

      unless response[:success]
        log_error("Failed to fetch execution", execution_id: execution_id, error: response[:error])
        return nil
      end

      response[:data][:execution]
    end

    def execute_integration(instance_id, input, context)
      # Call the execution endpoint on the backend
      # This delegates to the IntegrationExecutionService
      response = api_client.post("/api/v1/integrations/instances/#{instance_id}/execute", {
        input: input,
        context: context.merge(async: false) # Execute synchronously in this job
      })

      if response[:success]
        {
          success: true,
          result: response[:data][:result],
          execution_time_ms: response[:data][:execution_time_ms]
        }
      else
        {
          success: false,
          error: response[:error] || "Execution failed"
        }
      end
    rescue BackendApiClient::ApiError => e
      { success: false, error: "API error: #{e.message}" }
    end

    def update_execution_status(execution_id, status)
      api_client.patch("/api/v1/integrations/executions/#{execution_id}", {
        status: status,
        started_at: Time.current.iso8601
      })
    rescue StandardError => e
      log_error("Failed to update execution status", exception: e, execution_id: execution_id)
    end

    def complete_execution(execution_id, result)
      api_client.patch("/api/v1/integrations/executions/#{execution_id}", {
        status: "completed",
        completed_at: Time.current.iso8601,
        output_data: result[:result],
        execution_time_ms: result[:execution_time_ms]
      })

      increment_counter("integration_execution_success")
    rescue StandardError => e
      log_error("Failed to complete execution", exception: e, execution_id: execution_id)
    end

    def fail_execution(execution_id, error_message)
      api_client.patch("/api/v1/integrations/executions/#{execution_id}", {
        status: "failed",
        completed_at: Time.current.iso8601,
        error_message: error_message
      })

      increment_counter("integration_execution_failure")
    rescue StandardError => e
      log_error("Failed to record execution failure", exception: e, execution_id: execution_id)
    end
  end
end
