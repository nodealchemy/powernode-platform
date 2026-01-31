# frozen_string_literal: true

module Api
  module V1
    module Ai
      class A2aTasksController < ApplicationController
        include AuditLogging
        include ActionController::Live  # For SSE streaming

        before_action :set_task, only: %i[show cancel provide_input events artifacts artifact]
        before_action :validate_permissions

        # GET /api/v1/ai/a2a/tasks
        # List A2A tasks
        def index
          scope = current_user.account.ai_a2a_tasks

          # Apply filters
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.from_agent(params[:from_agent_id]) if params[:from_agent_id].present?
          scope = scope.to_agent(params[:to_agent_id]) if params[:to_agent_id].present?
          scope = scope.for_workflow_run(params[:workflow_run_id]) if params[:workflow_run_id].present?
          scope = scope.external_tasks if params[:external] == "true"
          scope = scope.internal_tasks if params[:external] == "false"

          # Date range
          if params[:since].present?
            scope = scope.where("created_at >= ?", Time.zone.parse(params[:since]))
          end

          # Sorting and pagination
          scope = scope.order(created_at: :desc)
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:task_summary),
            pagination: pagination_data(scope)
          )
          log_audit_event("ai.a2a_tasks.list", current_user.account)
        end

        # GET /api/v1/ai/a2a/tasks/:task_id
        def show
          render_success(task: @task.to_a2a_json)
          log_audit_event("ai.a2a_tasks.read", @task)
        end

        # GET /api/v1/ai/a2a/tasks/:task_id/details
        def details
          @task = find_task
          render_success(task: @task.task_details)
        end

        # POST /api/v1/ai/a2a/tasks
        # Submit a new A2A task (tasks/send)
        def create
          service = build_a2a_service

          begin
            result = if params[:external_endpoint].present?
                       service.submit_external_task(
                         endpoint_url: params[:external_endpoint],
                         message: task_message_params,
                         authentication: params[:authentication]&.to_unsafe_h || {},
                         from_agent_id: params[:from_agent_id],
                         metadata: params[:metadata]&.to_unsafe_h || {}
                       )
                     else
                       service.submit_task(
                         to_agent_card: params[:to_agent_card_id],
                         message: task_message_params,
                         from_agent: params[:from_agent_id],
                         metadata: params[:metadata]&.to_unsafe_h || {}
                       )
                     end

            render_success({ task: result.to_a2a_json }, status: :created)
            log_audit_event("ai.a2a_tasks.create", result)
          rescue ::Ai::A2a::Service::A2aError => e
            render_error(e.message, status: :unprocessable_content, code: e.code)
          end
        end

        # POST /api/v1/ai/a2a/tasks/:task_id/cancel
        def cancel
          service = build_a2a_service

          begin
            result = service.cancel_task(@task.task_id, reason: params[:reason])
            render_success(result)
            log_audit_event("ai.a2a_tasks.cancel", @task)
          rescue ::Ai::A2a::Service::A2aError => e
            render_error(e.message, status: :unprocessable_content, code: e.code)
          end
        end

        # POST /api/v1/ai/a2a/tasks/:task_id/input
        # Provide input for a task requiring input
        def provide_input
          service = build_a2a_service

          begin
            result = service.provide_input(@task.task_id, params[:input])
            render_success(result)
            log_audit_event("ai.a2a_tasks.provide_input", @task)
          rescue ::Ai::A2a::Service::A2aError => e
            render_error(e.message, status: :unprocessable_content, code: e.code)
          end
        end

        # GET /api/v1/ai/a2a/tasks/:task_id/events
        # SSE stream for task events
        def events
          response.headers["Content-Type"] = "text/event-stream"
          response.headers["Cache-Control"] = "no-cache"
          response.headers["X-Accel-Buffering"] = "no"

          # For SSE, we need to stream events
          sse = SSE.new(response.stream, retry: 300, event: "task.event")

          # Send initial status
          sse.write(@task.to_a2a_json, event: "task.status")

          # Get events since last check
          last_event_id = request.headers["Last-Event-ID"]
          since = last_event_id.present? ? Time.zone.parse(last_event_id) : nil

          service = build_a2a_service
          events_data = service.get_task_events(@task.task_id, since: since)

          events_data[:events].each do |event|
            sse.write(event, event: event[:type])
          end

          # If task is terminal, close the stream
          if @task.terminal?
            sse.write({ status: @task.status }, event: "task.complete")
          end
        rescue ActionController::Live::ClientDisconnected
          # Client disconnected, clean up
        ensure
          sse&.close
        end

        # GET /api/v1/ai/a2a/tasks/:task_id/events/poll
        # Polling alternative for events
        def events_poll
          @task = find_task
          service = build_a2a_service

          since = params[:since].present? ? Time.zone.parse(params[:since]) : nil
          events_data = service.get_task_events(@task.task_id, since: since, limit: params[:limit]&.to_i || 50)

          render_success(events_data)
        end

        # GET /api/v1/ai/a2a/tasks/:task_id/artifacts
        def artifacts
          render_success(artifacts: @task.a2a_artifacts)
        end

        # GET /api/v1/ai/a2a/tasks/:task_id/artifacts/:artifact_id
        def artifact
          service = build_a2a_service

          begin
            artifact_data = service.get_artifact(@task.task_id, params[:artifact_id])
            render_success(artifact: artifact_data)
          rescue ::Ai::A2a::Service::A2aError => e
            render_error(e.message, status: :not_found, code: e.code)
          end
        end

        # POST /api/v1/ai/a2a/tasks/:task_id/push_notifications
        def configure_push_notifications
          @task = find_task

          # Push notification configuration is handled at the task level
          @task.update!(
            push_notification_config: {
              url: params[:url],
              token: params[:token],
              authentication: params[:authentication]&.to_unsafe_h,
              events: params[:events]
            }
          )

          render_success(task: @task.to_a2a_json, message: "Push notifications configured")
        end

        private

        def set_task
          @task = find_task
        end

        def find_task
          task = current_user.account.ai_a2a_tasks.find_by(task_id: params[:task_id])
          task ||= current_user.account.ai_a2a_tasks.find_by(id: params[:task_id])

          unless task
            render_error("Task not found", status: :not_found)
            return
          end

          task
        end

        def build_a2a_service
          ::Ai::A2a::Service.new(account: current_user.account, user: current_user)
        end

        def validate_permissions
          return if current_worker || current_service

          permission_map = {
            %w[index show details events events_poll artifacts artifact] => "ai.agents.read",
            %w[create] => "ai.agents.execute",
            %w[cancel provide_input configure_push_notifications] => "ai.agents.execute"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end

        def task_message_params
          if params[:message].present?
            params[:message].to_unsafe_h
          elsif params[:text].present?
            { role: "user", parts: [{ type: "text", text: params[:text] }] }
          else
            {}
          end
        end

        # SSE helper class
        class SSE
          def initialize(stream, options = {})
            @stream = stream
            @options = options
          end

          def write(data, options = {})
            event = options[:event] || @options[:event]
            id = options[:id]
            retry_value = options[:retry] || @options[:retry]

            message = ""
            message += "event: #{event}\n" if event
            message += "id: #{id}\n" if id
            message += "retry: #{retry_value}\n" if retry_value
            message += "data: #{data.to_json}\n\n"

            @stream.write(message)
          end

          def close
            @stream.close
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
