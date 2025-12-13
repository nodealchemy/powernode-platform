# frozen_string_literal: true

class AiWorkflowScheduleJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_workflow_schedules', retry: 3

  def execute(schedule_id, options = {})
    @schedule_id = schedule_id
    @options = options

    log_info("Processing workflow schedule: #{schedule_id}")

    # Get schedule details
    schedule = fetch_schedule
    return unless schedule

    begin
      # Check if schedule is still active and due
      unless schedule_ready_for_execution?(schedule)
        log_info("Schedule #{schedule_id} is not ready for execution")
        return
      end

      # Execute the scheduled workflow
      result = execute_scheduled_workflow(schedule)

      if result['success']
        # Update schedule execution tracking
        update_schedule_tracking(schedule, result)

        # Schedule next execution
        schedule_next_execution(schedule)

        log_info("Scheduled workflow executed successfully: #{schedule_id}")
      else
        # Handle execution failure
        handle_schedule_failure(schedule, result)
      end

    rescue StandardError => e
      handle_schedule_error(schedule, e)
    end
  end

  # Class method to process due schedules (called by cron job or scheduler)
  def self.process_due_schedules
    response = backend_api_get('/api/v1/ai/workflow-schedules/due')
    return unless response['success']

    due_schedules = response['data']['schedules'] || []
    
    due_schedules.each do |schedule|
      perform_later(schedule['id'])
    end

    log_info("Queued #{due_schedules.size} due workflow schedules")
  end

  private

  def fetch_schedule
    response = backend_api_get("/api/v1/ai/workflow-schedules/#{@schedule_id}")
    
    if response['success']
      response['data']['schedule']
    else
      log_error("Failed to fetch schedule #{@schedule_id}: #{response['error']}")
      nil
    end
  end

  def schedule_ready_for_execution?(schedule)
    return false unless schedule['is_active']
    return false unless schedule['status'] == 'active'
    return false if schedule['next_execution_at'].nil?
    
    # Check if it's time to execute
    next_execution = Time.parse(schedule['next_execution_at'])
    return false if next_execution > Time.current

    # Check date range constraints
    if schedule['starts_at']
      starts_at = Time.parse(schedule['starts_at'])
      return false if Time.current < starts_at
    end

    if schedule['ends_at']
      ends_at = Time.parse(schedule['ends_at'])
      return false if Time.current > ends_at
    end

    # Check execution limits
    if schedule['max_executions']
      current_count = schedule['execution_count'] || 0
      return false if current_count >= schedule['max_executions']
    end

    # Check if workflow is already running (if configured to skip)
    if schedule.dig('configuration', 'skip_if_running')
      return false if workflow_currently_running?(schedule)
    end

    true
  end

  def workflow_currently_running?(schedule)
    workflow_id = schedule['ai_workflow_id']
    
    response = backend_api_get("/api/v1/ai/workflows/#{workflow_id}/runs", {
      status: 'running',
      limit: 1
    })
    
    return false unless response['success']
    
    running_runs = response['data']['runs'] || []
    running_runs.any?
  end

  def execute_scheduled_workflow(schedule)
    workflow_id = schedule['ai_workflow_id']
    input_variables = schedule['input_variables'] || {}
    
    # Add schedule context to input variables
    input_variables['_schedule_context'] = {
      'schedule_id' => schedule['id'],
      'schedule_name' => schedule['name'],
      'execution_count' => (schedule['execution_count'] || 0) + 1,
      'scheduled_at' => Time.current.iso8601,
      'cron_expression' => schedule['cron_expression']
    }

    # Execute the workflow
    response = backend_api_post("/api/v1/ai/workflows/#{workflow_id}/execute", {
      input_variables: input_variables,
      trigger_type: 'schedule',
      trigger_context: {
        'schedule_id' => schedule['id'],
        'execution_type' => 'scheduled'
      }
    })

    if response['success']
      {
        'success' => true,
        'workflow_run_id' => response['data']['workflow_run']['run_id'],
        'workflow_run' => response['data']['workflow_run']
      }
    else
      {
        'success' => false,
        'error_message' => response['error'] || 'Failed to execute scheduled workflow',
        'error_details' => response['data'] || {}
      }
    end
  end

  def update_schedule_tracking(schedule, execution_result)
    current_count = (schedule['execution_count'] || 0) + 1
    
    payload = {
      schedule: {
        execution_count: current_count,
        last_execution_at: Time.current.iso8601,
        metadata: schedule['metadata'].merge({
          'last_successful_execution' => {
            'at' => Time.current.iso8601,
            'run_id' => execution_result['workflow_run_id'],
            'execution_count' => current_count
          }
        })
      }
    }

    response = backend_api_patch("/api/v1/ai/workflow-schedules/#{@schedule_id}", payload)
    
    unless response['success']
      log_error("Failed to update schedule tracking: #{response['error']}")
    end
  end

  def schedule_next_execution(schedule)
    # Calculate next execution time
    response = backend_api_post("/api/v1/ai/workflow-schedules/#{@schedule_id}/calculate-next-execution")
    
    unless response['success']
      log_error("Failed to calculate next execution time: #{response['error']}")
    end
  end

  def handle_schedule_failure(schedule, result)
    error_message = result['error_message'] || 'Scheduled workflow execution failed'
    error_details = result['error_details'] || {}

    log_error("Scheduled workflow execution failed: #{error_message}")

    # Update schedule with error information
    payload = {
      schedule: {
        metadata: schedule['metadata'].merge({
          'last_execution_error' => {
            'at' => Time.current.iso8601,
            'error_message' => error_message,
            'error_details' => error_details,
            'error_count' => (schedule['metadata']['error_count'] || 0) + 1
          }
        })
      }
    }

    backend_api_patch("/api/v1/ai/workflow-schedules/#{@schedule_id}", payload)

    # Check if schedule should be disabled due to repeated failures
    error_count = schedule['metadata']['error_count'] || 0
    max_consecutive_errors = schedule.dig('configuration', 'max_consecutive_errors') || 10

    if error_count >= max_consecutive_errors
      disable_schedule_due_to_errors(schedule, error_count)
    else
      # Still schedule next execution
      schedule_next_execution(schedule)
    end
  end

  def handle_schedule_error(schedule, error)
    log_error("Schedule job error: #{error.message}")
    log_error(error.backtrace.join("\n"))

    # Update schedule with error information
    payload = {
      schedule: {
        status: 'error',
        metadata: schedule['metadata'].merge({
          'job_error' => {
            'at' => Time.current.iso8601,
            'error_message' => error.message,
            'exception_class' => error.class.name,
            'backtrace' => error.backtrace&.first(10)
          }
        })
      }
    }

    backend_api_patch("/api/v1/ai/workflow-schedules/#{@schedule_id}", payload)

    # Re-raise for retry mechanism
    raise error
  end

  def disable_schedule_due_to_errors(schedule, error_count)
    log_warn("Disabling schedule #{@schedule_id} due to #{error_count} consecutive errors")

    payload = {
      schedule: {
        status: 'disabled',
        is_active: false,
        metadata: schedule['metadata'].merge({
          'disabled_reason' => 'too_many_errors',
          'disabled_at' => Time.current.iso8601,
          'error_count_at_disable' => error_count
        })
      }
    }

    backend_api_patch("/api/v1/ai/workflow-schedules/#{@schedule_id}", payload)

    # Send notification if configured
    send_schedule_disabled_notification(schedule, error_count)
  end

  def send_schedule_disabled_notification(schedule, error_count)
    notification_config = schedule.dig('configuration', 'notifications')
    return unless notification_config && notification_config['on_disable']

    # Send notification via backend
    backend_api_post('/api/v1/notifications', {
      notification: {
        type: 'workflow_schedule_disabled',
        title: 'Workflow Schedule Disabled',
        message: "Schedule '#{schedule['name']}' has been disabled due to #{error_count} consecutive errors.",
        data: {
          schedule_id: schedule['id'],
          schedule_name: schedule['name'],
          error_count: error_count,
          workflow_id: schedule['ai_workflow_id']
        },
        recipients: [schedule['created_by']]
      }
    })
  end

  # Helper method for backend API calls with proper error handling
  def self.backend_api_get(path, params = {})
    BackendApiClient.get(path, params)
  rescue StandardError => e
    log_error("Backend API GET error: #{e.message}")
    { 'success' => false, 'error' => e.message }
  end
end