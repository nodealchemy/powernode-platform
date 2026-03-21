# frozen_string_literal: true

module System
  # CloudInstanceSyncJob - Syncs cloud instance states periodically
  #
  # This job runs periodically to synchronize the state of cloud instances
  # with their actual cloud provider status.
  #
  # @example Run cloud instance sync
  #   System::CloudInstanceSyncJob.perform_async
  #
  class CloudInstanceSyncJob < BaseJob
    sidekiq_options queue: 'system',
                    retry: 1,
                    dead: false

    # Execute cloud instance sync
    def execute
      log_info('Starting cloud instance sync')
      start_time = Time.current

      results = {
        nodes_processed: 0,
        instances_synced: 0,
        sync_jobs_queued: 0,
        errors: 0
      }

      begin
        # Get all enabled nodes with cloud/dynamic instances
        nodes = fetch_nodes_with_cloud_instances
        results[:nodes_processed] = nodes.size

        nodes.each do |node|
          begin
            sync_result = sync_node_instances(node)
            results[:instances_synced] += sync_result[:instances_count]
            results[:sync_jobs_queued] += sync_result[:jobs_queued]
          rescue StandardError => e
            results[:errors] += 1
            log_error('Failed to sync node instances', e, node_id: node['id'])
          end
        end

        duration = Time.current - start_time
        log_info('Cloud instance sync completed',
                 results: results,
                 duration: duration)

        track_performance_metric('cloud_instance_sync_duration', duration)
        increment_counter('cloud_instance_sync_runs')

        results.merge(duration: duration)

      rescue StandardError => e
        log_error('Cloud instance sync failed', e)
        track_error_metric('cloud_instance_sync_failed')
        raise
      end
    end

    private

    def fetch_nodes_with_cloud_instances
      with_api_retry do
        response = api_client.get('/api/v1/internal/system/nodes',
                                  enabled: true,
                                  has_cloud_instances: true)
        response['nodes'] || []
      end
    rescue BackendApiClient::ApiError => e
      log_error('Failed to fetch nodes with cloud instances', e)
      []
    end

    def sync_node_instances(node)
      node_id = node['id']
      instances_count = 0
      jobs_queued = 0

      # Get cloud and dynamic instances for this node
      instances = fetch_cloud_instances(node_id)
      instances_count = instances.size

      return { instances_count: 0, jobs_queued: 0 } if instances.empty?

      log_info("Syncing #{instances.size} cloud instances for node",
               node_id: node_id,
               node_name: node['name'])

      # Queue individual sync jobs for instances that need it
      instances.each do |instance|
        if needs_sync?(instance)
          System::NodeInstanceSyncJob.perform_async(instance['id'], nil, 'sync')
          jobs_queued += 1
        end
      end

      { instances_count: instances_count, jobs_queued: jobs_queued }
    end

    def fetch_cloud_instances(node_id)
      with_api_retry do
        response = api_client.get('/api/v1/internal/system/node_instances', {
          node_id: node_id,
          variety: %w[cloud dynamic]
        })
        response['node_instances'] || []
      end
    rescue BackendApiClient::ApiError => e
      log_error('Failed to fetch cloud instances', e, node_id: node_id)
      []
    end

    def needs_sync?(instance)
      # Sync if instance hasn't been synced recently
      return true unless instance['last_synced_at']

      last_synced = Time.parse(instance['last_synced_at']) rescue nil
      return true unless last_synced

      # Sync if last sync was more than sync_threshold ago
      sync_threshold = 30.minutes
      Time.current - last_synced > sync_threshold
    end
  end
end
