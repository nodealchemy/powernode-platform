# frozen_string_literal: true

module Devops
  module Docker
    class ContainerManager
      def initialize(host:, user: nil)
        @host = host
        @user = user
        @client = ApiClient.new(host)
      end

      def create_container(name:, image:, params: {})
        activity = create_activity("create", params: { name: name, image: image }.merge(params))

        begin
          activity.start!
          body = { Image: image }.merge(params.except(:name, :image))
          result = @client.container_create(name, body)
          activity.complete!(result)

          sync_container(result["Id"]) if result["Id"]
          result
        rescue ApiClient::ApiError => e
          activity.fail!(error: e.message)
          raise
        end
      end

      def start_container(container)
        activity = create_activity("start", container: container)

        begin
          activity.start!
          @client.container_start(container.docker_container_id)
          activity.complete!({})
          refresh_container(container)
        rescue ApiClient::ApiError => e
          activity.fail!(error: e.message)
          raise
        end
      end

      def stop_container(container, timeout: 10)
        activity = create_activity("stop", container: container, params: { timeout: timeout })

        begin
          activity.start!
          @client.container_stop(container.docker_container_id, timeout)
          activity.complete!({})
          refresh_container(container)
        rescue ApiClient::ApiError => e
          activity.fail!(error: e.message)
          raise
        end
      end

      def restart_container(container, timeout: 10)
        activity = create_activity("restart", container: container, params: { timeout: timeout })

        begin
          activity.start!
          @client.container_restart(container.docker_container_id, timeout)
          activity.complete!({})
          refresh_container(container)
        rescue ApiClient::ApiError => e
          activity.fail!(error: e.message)
          raise
        end
      end

      def remove_container(container, force: false)
        activity = create_activity("remove", container: container, params: { force: force })

        begin
          activity.start!
          @client.container_remove(container.docker_container_id, force: force)
          activity.complete!({})
          container.destroy!
        rescue ApiClient::ApiError => e
          activity.fail!(error: e.message)
          raise
        end
      end

      def container_logs(container, opts = {})
        @client.container_logs(container.docker_container_id, opts)
      end

      def container_stats(container)
        @client.container_stats(container.docker_container_id, stream: false)
      end

      def container_top(container)
        @client.container_top(container.docker_container_id)
      end

      # Execute a command inside a running container (non-interactive, 100KB output limit).
      def exec_command(container, command, opts = {})
        activity = create_activity("exec", container: container, params: { command: command })

        begin
          activity.start!
          exec_result = @client.container_exec_create(container.docker_container_id, command, opts)
          exec_id = exec_result["Id"]

          output = @client.container_exec_start(exec_id)
          inspect = @client.container_exec_inspect(exec_id)

          # Flatten log entries to a single string, truncate to 100KB
          output_text = if output.is_a?(Array)
                          output.map { |e| e[:message] }.join("\n")
                        else
                          output.to_s
                        end
          output_text = output_text.truncate(102_400)

          activity.complete!(exit_code: inspect["ExitCode"])

          {
            success: true,
            output: output_text,
            exit_code: inspect["ExitCode"]
          }
        rescue ApiClient::ApiError => e
          activity.fail!(error: e.message)
          raise
        end
      end

      private

      def create_activity(type, container: nil, params: {})
        @host.docker_activities.create!(
          activity_type: type,
          status: "pending",
          container: container,
          triggered_by: @user,
          trigger_source: "api",
          params: params
        )
      end

      def sync_container(container_id)
        data = @client.container_inspect(container_id)
        container = @host.docker_containers.find_or_initialize_by(docker_container_id: container_id)
        container.assign_attributes(
          name: data.dig("Name")&.sub(/\A\//, "") || "unknown",
          image: data.dig("Config", "Image") || "unknown",
          image_id: data["Image"],
          state: data.dig("State", "Status") || "created",
          status_text: data.dig("State", "Status"),
          command: data.dig("Config", "Cmd")&.join(" "),
          labels: data.dig("Config", "Labels") || {},
          last_seen_at: Time.current
        )
        container.save!
        container
      end

      def refresh_container(container)
        data = @client.container_inspect(container.docker_container_id)
        container.update!(
          state: data.dig("State", "Status") || container.state,
          status_text: data.dig("State", "Status"),
          started_at: data.dig("State", "StartedAt"),
          finished_at: data.dig("State", "FinishedAt"),
          restart_count: data["RestartCount"] || 0,
          last_seen_at: Time.current
        )
        container
      rescue ApiClient::NotFoundError
        container.update!(state: "removing", last_seen_at: Time.current)
        container
      end
    end
  end
end
