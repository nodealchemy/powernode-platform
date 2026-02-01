# frozen_string_literal: true

module A2a
  # PushNotificationService - Handles A2A push notification delivery
  # Implements webhook-based notifications for task events
  class PushNotificationService
    include HTTParty
    default_timeout 30

    def initialize(task:)
      @task = task
      @config = task.push_notification_config || {}
    end

    # Send a push notification for a task event
    def notify(event_type, event_data = {})
      return unless should_notify?(event_type)

      url = @config["url"]
      return unless url.present?

      payload = build_payload(event_type, event_data)
      headers = build_headers

      begin
        response = self.class.post(
          url,
          body: payload.to_json,
          headers: headers,
          timeout: 10
        )

        log_notification(event_type, response)
        response.success?
      rescue StandardError => e
        log_error(event_type, e)
        false
      end
    end

    # Notify on task status change
    def notify_status_change(previous_status, new_status)
      notify("status_change", {
        previous_status: previous_status,
        new_status: new_status
      })
    end

    # Notify on task completion
    def notify_completed
      notify("completed", {
        output: @task.output,
        artifacts: @task.a2a_artifacts,
        duration_ms: @task.duration_ms
      })
    end

    # Notify on task failure
    def notify_failed
      notify("failed", {
        error: @task.a2a_error,
        duration_ms: @task.duration_ms
      })
    end

    # Notify on artifact added
    def notify_artifact_added(artifact)
      notify("artifact_added", { artifact: artifact })
    end

    # Notify on input required
    def notify_input_required(input_schema = nil)
      notify("input_required", { input_schema: input_schema })
    end

    private

    def should_notify?(event_type)
      return true if @config["events"].blank?
      @config["events"].include?(event_type.to_s)
    end

    def build_payload(event_type, event_data)
      {
        jsonrpc: "2.0",
        method: "tasks/pushNotification",
        params: {
          taskId: @task.task_id,
          eventType: event_type,
          timestamp: Time.current.iso8601,
          task: @task.to_a2a_json,
          event: event_data
        }
      }
    end

    def build_headers
      headers = {
        "Content-Type" => "application/json",
        "User-Agent" => "Powernode-A2A/1.0"
      }

      # Add authentication if configured
      auth = @config["authentication"] || {}

      case auth["type"]
      when "bearer"
        headers["Authorization"] = "Bearer #{@config['token'] || auth['token']}"
      when "api_key"
        header_name = auth["header_name"] || "X-API-Key"
        headers[header_name] = auth["api_key"]
      when "basic"
        credentials = Base64.strict_encode64("#{auth['username']}:#{auth['password']}")
        headers["Authorization"] = "Basic #{credentials}"
      end

      headers
    end

    def log_notification(event_type, response)
      Rails.logger.info(
        "A2A push notification sent: task=#{@task.task_id} event=#{event_type} " \
        "status=#{response.code} url=#{@config['url']}"
      )
    end

    def log_error(event_type, error)
      Rails.logger.error(
        "A2A push notification failed: task=#{@task.task_id} event=#{event_type} " \
        "error=#{error.message} url=#{@config['url']}"
      )
    end

    class << self
      # Send notification for a task (class method for background jobs)
      def send_notification(task_id, event_type, event_data = {})
        task = ::Ai::A2aTask.find(task_id)
        new(task: task).notify(event_type, event_data)
      end
    end
  end
end
