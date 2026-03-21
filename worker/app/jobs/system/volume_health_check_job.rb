# frozen_string_literal: true

module System
  # VolumeHealthCheckJob - Verifies provider volume health
  #
  # This job runs periodically to check the health of provider volumes,
  # ensure proper attachment states, and queue corrective actions if needed.
  #
  # @example Run volume health check
  #   System::VolumeHealthCheckJob.perform_async
  #
  class VolumeHealthCheckJob < BaseJob
    sidekiq_options queue: 'system',
                    retry: 1,
                    dead: false

    # Execute volume health check
    def execute
      log_info('Starting volume health check')
      start_time = Time.current

      results = {
        volumes_checked: 0,
        unhealthy_volumes: 0,
        volumes_needing_provision: 0,
        volumes_needing_attach: 0,
        volumes_needing_detach: 0,
        actions_queued: 0
      }

      begin
        # Get all active volumes
        volumes = fetch_volumes
        results[:volumes_checked] = volumes.size

        volumes.each do |volume|
          check_result = check_volume_health(volume)

          results[:unhealthy_volumes] += 1 unless check_result[:healthy]
          results[:actions_queued] += check_result[:actions_queued]

          case check_result[:issue]
          when :needs_provision
            results[:volumes_needing_provision] += 1
          when :needs_attach
            results[:volumes_needing_attach] += 1
          when :needs_detach
            results[:volumes_needing_detach] += 1
          end
        end

        duration = Time.current - start_time
        log_info('Volume health check completed',
                 results: results,
                 duration: duration)

        track_performance_metric('volume_health_check_duration', duration)
        increment_counter('volume_health_check_runs')

        results.merge(duration: duration)

      rescue StandardError => e
        log_error('Volume health check failed', e)
        track_error_metric('volume_health_check_failed')
        raise
      end
    end

    private

    def fetch_volumes
      with_api_retry do
        response = api_client.get('/api/v1/internal/system/provider_volumes', for_health_check: true)
        response['provider_volumes'] || []
      end
    rescue BackendApiClient::ApiError => e
      log_error('Failed to fetch volumes for health check', e)
      []
    end

    def check_volume_health(volume)
      volume_id = volume['id']
      status = volume['status']
      node_instance_id = volume['node_instance_id']
      active_instance_id = volume['active_instance_id']
      healthy = true
      issue = nil
      actions_queued = 0

      # Check for pending volumes that need provisioning
      if status == 'pending'
        healthy = false
        issue = :needs_provision
        log_info('Volume needs provisioning', volume_id: volume_id)

        System::VolumeManagementJob.perform_async(volume_id, nil, 'provision')
        actions_queued += 1
      end

      # Check for volumes that should be attached but aren't
      if status == 'available' && node_instance_id.present?
        # Volume has an assigned instance but isn't attached
        # Check if instance is running
        instance_running = check_instance_running(node_instance_id)

        if instance_running
          healthy = false
          issue = :needs_attach
          log_info('Volume should be attached',
                   volume_id: volume_id,
                   node_instance_id: node_instance_id)

          System::VolumeManagementJob.perform_async(volume_id, nil, 'attach')
          actions_queued += 1
        end
      end

      # Check for volumes that should be detached
      if status == 'attached' && node_instance_id.blank?
        healthy = false
        issue = :needs_detach
        log_info('Volume should be detached',
                 volume_id: volume_id,
                 active_instance_id: active_instance_id)

        System::VolumeManagementJob.perform_async(volume_id, nil, 'detach')
        actions_queued += 1
      end

      # Check for stale provisioning status
      if status == 'provisioning'
        provisioning_duration = Time.current - Time.parse(volume['updated_at']) rescue nil
        if provisioning_duration && provisioning_duration > 30.minutes
          healthy = false
          log_warn('Volume stuck in provisioning state',
                   volume_id: volume_id,
                   duration: provisioning_duration)

          # Queue recovery
          System::VolumeManagementJob.perform_async(volume_id, nil, 'recover')
          actions_queued += 1
        end
      end

      { healthy: healthy, issue: issue, actions_queued: actions_queued }
    rescue StandardError => e
      log_error('Volume health check failed', e, volume_id: volume_id)
      { healthy: false, issue: nil, actions_queued: 0 }
    end

    def check_instance_running(instance_id)
      return false unless instance_id.present?

      with_api_retry do
        instance = api_client.get("/api/v1/internal/system/node_instances/#{instance_id}")
        instance['status'] == 'running'
      end
    rescue BackendApiClient::ApiError
      false
    end
  end
end
