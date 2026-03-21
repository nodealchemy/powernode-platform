# frozen_string_literal: true

module System
  # Service for performing maintenance operations on nodes
  # Handles cleanup, health checks, and scheduled maintenance
  class NodeMaintenanceService
    class MaintenanceError < StandardError; end

    MAINTENANCE_TASKS = %w[
      health_check
      resource_cleanup
      security_update
      config_sync
      log_rotation
      certificate_renewal
    ].freeze

    # Run maintenance on a node
    #
    # @param node [System::Node] The node
    # @param tasks [Array<String>] Tasks to run (default: all)
    # @param options [Hash] Maintenance options
    # @return [Hash] Result with :success, :results, :error
    def self.run_maintenance(node:, tasks: nil, options: {})
      new.run_maintenance(node: node, tasks: tasks, options: options)
    end

    # Run maintenance on all enabled nodes for an account
    #
    # @param account [Account] The account
    # @param tasks [Array<String>] Tasks to run (default: health_check only)
    # @param options [Hash] Maintenance options
    # @return [Hash] Result with :success, :results, :error
    def self.run_account_maintenance(account:, tasks: nil, options: {})
      new.run_account_maintenance(account: account, tasks: tasks, options: options)
    end

    def run_maintenance(node:, tasks: nil, options: {})
      validate_node!(node)

      unless node.enabled?
        return { success: false, error: "Node is disabled" }
      end

      tasks ||= MAINTENANCE_TASKS
      tasks = Array(tasks) & MAINTENANCE_TASKS

      Rails.logger.info("[NodeMaintenanceService] Running maintenance on #{node.name}: #{tasks.join(', ')}")

      results = {}
      all_success = true

      tasks.each do |task|
        Rails.logger.info("[NodeMaintenanceService] Task: #{task}")
        result = send("task_#{task}", node, options)
        results[task] = result
        all_success = false unless result[:success]
      end

      # Update node maintenance timestamp
      update_maintenance_record(node, results)

      {
        success: all_success,
        results: results,
        tasks_run: tasks.count,
        tasks_succeeded: results.count { |_, r| r[:success] },
        tasks_failed: results.count { |_, r| !r[:success] }
      }
    end

    def run_account_maintenance(account:, tasks: nil, options: {})
      nodes = ::System::Node.where(account: account, enabled: true)

      if nodes.empty?
        return { success: true, message: "No enabled nodes for account" }
      end

      Rails.logger.info("[NodeMaintenanceService] Running maintenance on #{nodes.count} nodes for account #{account.id}")

      results = []
      all_success = true

      nodes.find_each do |node|
        result = run_maintenance(node: node, tasks: tasks, options: options)
        results << { node_id: node.id, node_name: node.name, result: result }
        all_success = false unless result[:success]
      end

      {
        success: all_success,
        results: results,
        total_nodes: nodes.count,
        nodes_succeeded: results.count { |r| r[:result][:success] },
        nodes_failed: results.count { |r| !r[:result][:success] }
      }
    end

    private

    def validate_node!(node)
      raise ArgumentError, "Node required" unless node
      raise ArgumentError, "Node must be a System::Node" unless node.is_a?(::System::Node)
    end

    # Task: Health Check - Verify node and instance health
    def task_health_check(node, options)
      Rails.logger.info("[NodeMaintenanceService] Running health check for #{node.name}")

      start_time = Time.current
      issues = []

      # Check node configuration
      if node.ssh_key.blank?
        issues << "No SSH key configured"
      end

      # Check instances
      instances = node.node_instances
      running = instances.where(status: "running").count
      total = instances.count

      # Check for stuck instances
      stuck = instances.where(status: %w[starting stopping rebooting]).where("updated_at < ?", 30.minutes.ago)
      if stuck.any?
        issues << "#{stuck.count} instances stuck in transitional state"
      end

      # Ping running instances
      instances.where(status: "running").find_each do |instance|
        result = check_instance_connectivity(instance)
        unless result[:success]
          issues << "Instance #{instance.name} not reachable"
        end
      end

      {
        success: issues.empty?,
        duration: Time.current - start_time,
        running_instances: running,
        total_instances: total,
        issues: issues
      }
    end

    # Task: Resource Cleanup - Clean up orphaned resources
    def task_resource_cleanup(node, options)
      Rails.logger.info("[NodeMaintenanceService] Running resource cleanup for #{node.name}")

      start_time = Time.current
      cleaned = []

      # Clean up terminated instances older than retention period
      retention_days = options[:retention_days] || 30
      cutoff = retention_days.days.ago

      terminated = node.node_instances.where(status: "terminated").where("updated_at < ?", cutoff)
      terminated_count = terminated.count

      if terminated_count > 0 && options[:delete_terminated]
        terminated.destroy_all
        cleaned << "Deleted #{terminated_count} old terminated instances"
      elsif terminated_count > 0
        cleaned << "Found #{terminated_count} terminated instances eligible for cleanup"
      end

      # Clean up orphaned volumes
      orphaned_volumes = find_orphaned_volumes(node)
      if orphaned_volumes.any?
        cleaned << "Found #{orphaned_volumes.count} orphaned volumes"
      end

      # Clean up failed operations older than retention
      failed_ops = ::System::Operation
                     .where(operable: node)
                     .where(status: "failed")
                     .where("completed_at < ?", cutoff)

      if failed_ops.any? && options[:clean_failed_operations]
        failed_ops.delete_all
        cleaned << "Cleaned #{failed_ops.count} old failed operations"
      end

      {
        success: true,
        duration: Time.current - start_time,
        actions: cleaned
      }
    end

    # Task: Security Update - Check for and apply security updates
    def task_security_update(node, options)
      Rails.logger.info("[NodeMaintenanceService] Checking security updates for #{node.name}")

      start_time = Time.current
      updates_needed = []
      updates_applied = []

      node.node_instances.where(status: "running").find_each do |instance|
        # Check for available security updates
        result = SshExecutionService.execute(
          instance: instance,
          command: check_updates_command(instance),
          sudo: true
        )

        if result[:success] && result[:stdout].present?
          updates = parse_updates(result[:stdout])
          if updates.any?
            updates_needed << { instance: instance.name, count: updates.count }

            # Apply updates if requested
            if options[:apply_updates]
              apply_result = apply_security_updates(instance)
              if apply_result[:success]
                updates_applied << instance.name
              end
            end
          end
        end
      end

      {
        success: true,
        duration: Time.current - start_time,
        updates_needed: updates_needed,
        updates_applied: updates_applied
      }
    end

    # Task: Config Sync - Sync node configuration to instances
    def task_config_sync(node, options)
      Rails.logger.info("[NodeMaintenanceService] Syncing configuration for #{node.name}")

      start_time = Time.current
      synced = []
      failed = []

      node.node_instances.where(status: "running").find_each do |instance|
        result = SshExecutionService.sync(instance: instance)

        if result[:success]
          synced << instance.name
        else
          failed << { instance: instance.name, error: result[:error] }
        end
      end

      {
        success: failed.empty?,
        duration: Time.current - start_time,
        synced: synced,
        failed: failed
      }
    end

    # Task: Log Rotation - Trigger log rotation on instances
    def task_log_rotation(node, options)
      Rails.logger.info("[NodeMaintenanceService] Running log rotation for #{node.name}")

      start_time = Time.current
      rotated = []

      node.node_instances.where(status: "running").find_each do |instance|
        result = SshExecutionService.execute(
          instance: instance,
          command: "logrotate -f /etc/logrotate.conf",
          sudo: true
        )

        if result[:success]
          rotated << instance.name
        end
      end

      {
        success: true,
        duration: Time.current - start_time,
        rotated: rotated
      }
    end

    # Task: Certificate Renewal - Check and renew SSL certificates
    def task_certificate_renewal(node, options)
      Rails.logger.info("[NodeMaintenanceService] Checking certificates for #{node.name}")

      start_time = Time.current
      expiring = []
      renewed = []

      # Check for certificates expiring within threshold
      threshold_days = options[:cert_threshold_days] || 30

      node.node_instances.where(status: "running").find_each do |instance|
        result = check_certificates(instance, threshold_days)

        if result[:expiring].any?
          expiring << { instance: instance.name, certs: result[:expiring] }

          # Attempt renewal if requested
          if options[:auto_renew]
            renew_result = renew_certificates(instance)
            if renew_result[:success]
              renewed << instance.name
            end
          end
        end
      end

      {
        success: true,
        duration: Time.current - start_time,
        expiring_certificates: expiring,
        renewed: renewed
      }
    end

    def check_instance_connectivity(instance)
      ssh_ip = instance.ssh_ip_address
      return { success: false, error: "No SSH IP" } unless ssh_ip.present?

      # Simple connectivity check - execute echo command
      result = SshExecutionService.execute(
        instance: instance,
        command: "echo pong",
        sudo: false
      )

      { success: result[:success] && result[:stdout]&.include?("pong") }
    end

    def find_orphaned_volumes(node)
      # Find volumes attached to terminated or non-existent instances
      instance_ids = node.node_instances.pluck(:id)

      ::System::ProviderVolumeMember
        .where.not(node_instance_id: instance_ids)
        .includes(:provider_volume)
        .map(&:provider_volume)
        .compact
    end

    def check_updates_command(instance)
      # Detect package manager and generate appropriate command
      # This would be determined by the platform in production
      "apt list --upgradable 2>/dev/null || yum check-update 2>/dev/null || true"
    end

    def parse_updates(output)
      # Parse update output (simplified)
      output.lines.select { |l| l.include?("/") || l.include?("updates") }
    end

    def apply_security_updates(instance)
      result = SshExecutionService.execute(
        instance: instance,
        command: "apt-get update && apt-get upgrade -y --only-upgrade 2>/dev/null || yum update -y 2>/dev/null || true",
        sudo: true
      )

      { success: result[:exit_code] == 0 }
    end

    def check_certificates(instance, threshold_days)
      # Check Let's Encrypt or system certificates
      result = SshExecutionService.execute(
        instance: instance,
        command: "find /etc/letsencrypt/live -name 'cert.pem' -exec openssl x509 -in {} -checkend #{threshold_days * 86400} \\; 2>/dev/null || true",
        sudo: true
      )

      expiring = []
      if result[:stdout]&.include?("Certificate will expire")
        expiring << "letsencrypt"
      end

      { expiring: expiring }
    end

    def renew_certificates(instance)
      result = SshExecutionService.execute(
        instance: instance,
        command: "certbot renew --quiet",
        sudo: true
      )

      { success: result[:exit_code] == 0 }
    end

    def update_maintenance_record(node, results)
      config = node.config || {}
      config["last_maintenance"] = {
        "ran_at" => Time.current.iso8601,
        "tasks" => results.keys,
        "success" => results.values.all? { |r| r[:success] }
      }

      node.update!(config: config)
    end
  end
end
