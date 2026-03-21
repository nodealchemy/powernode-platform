# frozen_string_literal: true

module System
  # Service for performing maintenance operations on individual instances
  # Handles instance-level cleanup, optimization, and monitoring
  class InstanceMaintenanceService
    class MaintenanceError < StandardError; end

    MAINTENANCE_TASKS = %w[
      health_check
      disk_cleanup
      memory_check
      process_audit
      network_check
      service_status
    ].freeze

    # Run maintenance on an instance
    #
    # @param instance [System::NodeInstance] The instance
    # @param tasks [Array<String>] Tasks to run (default: all)
    # @param options [Hash] Maintenance options
    # @return [Hash] Result with :success, :results, :error
    def self.run_maintenance(instance:, tasks: nil, options: {})
      new.run_maintenance(instance: instance, tasks: tasks, options: options)
    end

    def run_maintenance(instance:, tasks: nil, options: {})
      validate_instance!(instance)

      unless instance.active?
        return { success: false, error: "Instance is not running" }
      end

      tasks ||= MAINTENANCE_TASKS
      tasks = Array(tasks) & MAINTENANCE_TASKS

      Rails.logger.info("[InstanceMaintenanceService] Running maintenance on #{instance.name}: #{tasks.join(', ')}")

      results = {}
      all_success = true

      tasks.each do |task|
        Rails.logger.info("[InstanceMaintenanceService] Task: #{task}")
        result = send("task_#{task}", instance, options)
        results[task] = result
        all_success = false unless result[:success]
      end

      # Update instance maintenance timestamp
      update_maintenance_record(instance, results)

      {
        success: all_success,
        results: results,
        tasks_run: tasks.count,
        tasks_succeeded: results.count { |_, r| r[:success] },
        tasks_failed: results.count { |_, r| !r[:success] }
      }
    end

    private

    def validate_instance!(instance)
      raise ArgumentError, "Instance required" unless instance
      raise ArgumentError, "Instance must be a System::NodeInstance" unless instance.is_a?(::System::NodeInstance)
    end

    # Task: Health Check - Comprehensive instance health verification
    def task_health_check(instance, options)
      Rails.logger.info("[InstanceMaintenanceService] Running health check for #{instance.name}")

      start_time = Time.current
      checks = {}
      issues = []

      # SSH connectivity
      ssh_check = check_ssh_connectivity(instance)
      checks[:ssh] = ssh_check[:success]
      issues << "SSH connectivity failed" unless ssh_check[:success]

      return { success: false, error: "Cannot connect to instance", checks: checks } unless ssh_check[:success]

      # System uptime
      uptime = get_system_uptime(instance)
      checks[:uptime] = uptime[:success]
      checks[:uptime_seconds] = uptime[:seconds] if uptime[:success]

      # Load average
      load = get_load_average(instance)
      checks[:load] = load[:success]
      if load[:success]
        checks[:load_1m] = load[:load_1m]
        checks[:load_5m] = load[:load_5m]
        checks[:load_15m] = load[:load_15m]

        # Check for high load (> 2x CPU count)
        if load[:load_1m] > (get_cpu_count(instance) * 2)
          issues << "High load average: #{load[:load_1m]}"
        end
      end

      # Disk space
      disk = check_disk_space(instance)
      checks[:disk] = disk[:success]
      if disk[:success] && disk[:partitions]
        critical_partitions = disk[:partitions].select { |p| p[:used_percent] > 90 }
        if critical_partitions.any?
          issues << "Disk space critical: #{critical_partitions.map { |p| "#{p[:mount]} (#{p[:used_percent]}%)" }.join(', ')}"
        end
      end

      # Memory usage
      memory = check_memory_usage(instance)
      checks[:memory] = memory[:success]
      if memory[:success]
        checks[:memory_used_percent] = memory[:used_percent]
        if memory[:used_percent] > 90
          issues << "Memory usage critical: #{memory[:used_percent]}%"
        end
      end

      {
        success: issues.empty?,
        duration: Time.current - start_time,
        checks: checks,
        issues: issues
      }
    end

    # Task: Disk Cleanup - Free up disk space
    def task_disk_cleanup(instance, options)
      Rails.logger.info("[InstanceMaintenanceService] Running disk cleanup for #{instance.name}")

      start_time = Time.current
      freed_mb = 0
      actions = []

      # Clean package manager cache
      result = SshExecutionService.execute(
        instance: instance,
        command: cleanup_package_cache_command,
        sudo: true
      )
      if result[:success]
        actions << "Cleaned package cache"
      end

      # Clean old logs
      if options[:clean_logs]
        result = SshExecutionService.execute(
          instance: instance,
          command: "find /var/log -type f -name '*.gz' -mtime +#{options[:log_retention_days] || 30} -delete",
          sudo: true
        )
        if result[:success]
          actions << "Cleaned old log files"
        end
      end

      # Clean temp files
      result = SshExecutionService.execute(
        instance: instance,
        command: "find /tmp -type f -atime +7 -delete 2>/dev/null || true",
        sudo: true
      )
      if result[:success]
        actions << "Cleaned temp files"
      end

      # Clean old kernels (if requested)
      if options[:clean_old_kernels]
        result = SshExecutionService.execute(
          instance: instance,
          command: clean_old_kernels_command,
          sudo: true
        )
        if result[:success]
          actions << "Cleaned old kernels"
        end
      end

      # Get freed space
      after = check_disk_space(instance)

      {
        success: true,
        duration: Time.current - start_time,
        actions: actions,
        disk_after: after[:partitions]
      }
    end

    # Task: Memory Check - Detailed memory analysis
    def task_memory_check(instance, options)
      Rails.logger.info("[InstanceMaintenanceService] Running memory check for #{instance.name}")

      start_time = Time.current

      result = SshExecutionService.execute(
        instance: instance,
        command: "free -m",
        sudo: false
      )

      unless result[:success]
        return { success: false, error: "Failed to get memory info" }
      end

      memory_info = parse_free_output(result[:stdout])

      # Get swap usage
      swap_result = SshExecutionService.execute(
        instance: instance,
        command: "cat /proc/swaps",
        sudo: false
      )
      swap_info = parse_swap_info(swap_result[:stdout]) if swap_result[:success]

      # Get top memory consumers
      top_result = SshExecutionService.execute(
        instance: instance,
        command: "ps aux --sort=-%mem | head -11",
        sudo: false
      )
      top_processes = parse_top_processes(top_result[:stdout]) if top_result[:success]

      # Check for OOM killer activity
      oom_result = SshExecutionService.execute(
        instance: instance,
        command: "dmesg | grep -i 'out of memory' | tail -5",
        sudo: true
      )
      oom_events = oom_result[:stdout]&.lines&.count || 0

      recommendations = []
      if memory_info[:used_percent] > 80
        recommendations << "Consider adding more memory"
      end
      if swap_info && swap_info[:used_percent] > 50
        recommendations << "High swap usage - may indicate memory pressure"
      end
      if oom_events > 0
        recommendations << "OOM killer has been active - review memory allocation"
      end

      {
        success: true,
        duration: Time.current - start_time,
        memory: memory_info,
        swap: swap_info,
        top_processes: top_processes&.first(5),
        oom_events: oom_events,
        recommendations: recommendations
      }
    end

    # Task: Process Audit - Check running processes
    def task_process_audit(instance, options)
      Rails.logger.info("[InstanceMaintenanceService] Running process audit for #{instance.name}")

      start_time = Time.current

      # Get process count
      ps_result = SshExecutionService.execute(
        instance: instance,
        command: "ps aux | wc -l",
        sudo: false
      )
      process_count = ps_result[:stdout]&.strip&.to_i || 0

      # Get zombie processes
      zombie_result = SshExecutionService.execute(
        instance: instance,
        command: "ps aux | grep -w Z | grep -v grep | wc -l",
        sudo: false
      )
      zombie_count = zombie_result[:stdout]&.strip&.to_i || 0

      # Get defunct processes
      defunct_result = SshExecutionService.execute(
        instance: instance,
        command: "ps aux | grep defunct | grep -v grep",
        sudo: false
      )
      defunct_processes = defunct_result[:stdout]&.lines&.map(&:strip) || []

      # Check for long-running processes
      long_running_result = SshExecutionService.execute(
        instance: instance,
        command: "ps -eo pid,etime,cmd --sort=-etime | head -11",
        sudo: false
      )
      long_running = parse_long_running_processes(long_running_result[:stdout]) if long_running_result[:success]

      # Check for high CPU processes
      high_cpu_result = SshExecutionService.execute(
        instance: instance,
        command: "ps aux --sort=-%cpu | head -6",
        sudo: false
      )
      high_cpu = parse_top_processes(high_cpu_result[:stdout]) if high_cpu_result[:success]

      issues = []
      issues << "#{zombie_count} zombie processes detected" if zombie_count > 0
      issues << "#{defunct_processes.count} defunct processes" if defunct_processes.any?

      {
        success: issues.empty?,
        duration: Time.current - start_time,
        process_count: process_count,
        zombie_count: zombie_count,
        defunct_processes: defunct_processes,
        long_running: long_running&.first(5),
        high_cpu_processes: high_cpu&.first(5),
        issues: issues
      }
    end

    # Task: Network Check - Verify network connectivity
    def task_network_check(instance, options)
      Rails.logger.info("[InstanceMaintenanceService] Running network check for #{instance.name}")

      start_time = Time.current
      checks = {}

      # DNS resolution
      dns_result = SshExecutionService.execute(
        instance: instance,
        command: "host google.com 2>&1 || nslookup google.com 2>&1",
        sudo: false
      )
      checks[:dns] = dns_result[:success] && !dns_result[:stdout].include?("not found")

      # Internet connectivity
      ping_result = SshExecutionService.execute(
        instance: instance,
        command: "ping -c 3 8.8.8.8 2>&1 || true",
        sudo: false
      )
      checks[:internet] = ping_result[:stdout]&.include?("bytes from")

      # Get network interfaces
      interfaces_result = SshExecutionService.execute(
        instance: instance,
        command: "ip -o addr show | awk '{print $2, $4}'",
        sudo: false
      )
      checks[:interfaces] = parse_interfaces(interfaces_result[:stdout]) if interfaces_result[:success]

      # Get active connections count
      connections_result = SshExecutionService.execute(
        instance: instance,
        command: "ss -tuln | wc -l",
        sudo: false
      )
      checks[:listening_ports] = connections_result[:stdout]&.strip&.to_i || 0

      # Get established connections
      established_result = SshExecutionService.execute(
        instance: instance,
        command: "ss -tun state established | wc -l",
        sudo: false
      )
      checks[:established_connections] = established_result[:stdout]&.strip&.to_i || 0

      issues = []
      issues << "DNS resolution failed" unless checks[:dns]
      issues << "No internet connectivity" unless checks[:internet]

      {
        success: issues.empty?,
        duration: Time.current - start_time,
        checks: checks,
        issues: issues
      }
    end

    # Task: Service Status - Check critical services
    def task_service_status(instance, options)
      Rails.logger.info("[InstanceMaintenanceService] Checking service status for #{instance.name}")

      start_time = Time.current

      # Get list of services to check from node configuration or defaults
      services_to_check = options[:services] || %w[sshd cron]

      # Add module-defined services
      node = instance.node
      if node
        node.node_module_assignments.includes(node_module: :node_module_copy_paths).each do |assignment|
          mod = assignment.node_module
          if mod.file_spec.is_a?(Hash) && mod.file_spec["services"]
            services_to_check += mod.file_spec["services"]
          end
        end
      end

      services_to_check.uniq!

      service_statuses = {}
      failed_services = []

      services_to_check.each do |service|
        result = SshExecutionService.execute(
          instance: instance,
          command: "systemctl is-active #{service} 2>/dev/null || service #{service} status 2>/dev/null",
          sudo: true
        )

        status = if result[:stdout]&.strip == "active"
                   "running"
                 elsif result[:success]
                   "running"
                 else
                   "stopped"
                 end

        service_statuses[service] = status
        failed_services << service if status == "stopped"
      end

      # Auto-restart failed services if requested
      restarted = []
      if options[:auto_restart] && failed_services.any?
        failed_services.each do |service|
          result = SshExecutionService.execute(
            instance: instance,
            command: "systemctl start #{service} 2>/dev/null || service #{service} start 2>/dev/null",
            sudo: true
          )
          restarted << service if result[:success]
        end
      end

      {
        success: failed_services.empty? || restarted.count == failed_services.count,
        duration: Time.current - start_time,
        services: service_statuses,
        failed: failed_services,
        restarted: restarted
      }
    end

    # Helper methods

    def check_ssh_connectivity(instance)
      result = SshExecutionService.execute(
        instance: instance,
        command: "echo connected",
        sudo: false
      )
      { success: result[:success] && result[:stdout]&.include?("connected") }
    end

    def get_system_uptime(instance)
      result = SshExecutionService.execute(
        instance: instance,
        command: "cat /proc/uptime | awk '{print $1}'",
        sudo: false
      )

      if result[:success]
        { success: true, seconds: result[:stdout].strip.to_f }
      else
        { success: false }
      end
    end

    def get_load_average(instance)
      result = SshExecutionService.execute(
        instance: instance,
        command: "cat /proc/loadavg",
        sudo: false
      )

      if result[:success]
        parts = result[:stdout].strip.split
        {
          success: true,
          load_1m: parts[0].to_f,
          load_5m: parts[1].to_f,
          load_15m: parts[2].to_f
        }
      else
        { success: false }
      end
    end

    def get_cpu_count(instance)
      result = SshExecutionService.execute(
        instance: instance,
        command: "nproc",
        sudo: false
      )
      result[:stdout]&.strip&.to_i || 1
    end

    def check_disk_space(instance)
      result = SshExecutionService.execute(
        instance: instance,
        command: "df -h --output=target,size,used,avail,pcent",
        sudo: false
      )

      if result[:success]
        partitions = parse_df_output(result[:stdout])
        { success: true, partitions: partitions }
      else
        { success: false }
      end
    end

    def check_memory_usage(instance)
      result = SshExecutionService.execute(
        instance: instance,
        command: "free -m | grep Mem | awk '{print $2, $3, $4}'",
        sudo: false
      )

      if result[:success]
        parts = result[:stdout].strip.split
        total = parts[0].to_i
        used = parts[1].to_i
        {
          success: true,
          total_mb: total,
          used_mb: used,
          free_mb: parts[2].to_i,
          used_percent: total > 0 ? ((used.to_f / total) * 100).round(1) : 0
        }
      else
        { success: false }
      end
    end

    def parse_df_output(output)
      return [] unless output

      lines = output.lines.drop(1) # Skip header
      lines.map do |line|
        parts = line.strip.split
        next if parts.length < 5

        {
          mount: parts[0],
          size: parts[1],
          used: parts[2],
          available: parts[3],
          used_percent: parts[4].to_i
        }
      end.compact
    end

    def parse_free_output(output)
      return {} unless output

      mem_line = output.lines.find { |l| l.start_with?("Mem:") }
      return {} unless mem_line

      parts = mem_line.split
      total = parts[1].to_i
      used = parts[2].to_i

      {
        total_mb: total,
        used_mb: used,
        free_mb: parts[3].to_i,
        shared_mb: parts[4].to_i,
        buff_cache_mb: parts[5].to_i,
        available_mb: parts[6].to_i,
        used_percent: total > 0 ? ((used.to_f / total) * 100).round(1) : 0
      }
    end

    def parse_swap_info(output)
      return nil unless output

      lines = output.lines.drop(1)
      return nil if lines.empty?

      parts = lines.first.split
      return nil if parts.length < 4

      size = parts[2].to_i
      used = parts[3].to_i

      {
        device: parts[0],
        type: parts[1],
        size_kb: size,
        used_kb: used,
        used_percent: size > 0 ? ((used.to_f / size) * 100).round(1) : 0
      }
    end

    def parse_top_processes(output)
      return [] unless output

      output.lines.drop(1).map do |line|
        parts = line.split
        next if parts.length < 11

        {
          user: parts[0],
          pid: parts[1].to_i,
          cpu_percent: parts[2].to_f,
          mem_percent: parts[3].to_f,
          command: parts[10..-1].join(" ")
        }
      end.compact
    end

    def parse_long_running_processes(output)
      return [] unless output

      output.lines.drop(1).map do |line|
        parts = line.split
        next if parts.length < 3

        {
          pid: parts[0].to_i,
          elapsed: parts[1],
          command: parts[2..-1].join(" ")
        }
      end.compact
    end

    def parse_interfaces(output)
      return [] unless output

      output.lines.map do |line|
        parts = line.strip.split
        next if parts.length < 2

        { interface: parts[0], address: parts[1] }
      end.compact
    end

    def cleanup_package_cache_command
      "apt-get clean 2>/dev/null || yum clean all 2>/dev/null || dnf clean all 2>/dev/null || true"
    end

    def clean_old_kernels_command
      "apt-get autoremove -y 2>/dev/null || package-cleanup --oldkernels --count=2 -y 2>/dev/null || true"
    end

    def update_maintenance_record(instance, results)
      config = instance.config || {}
      config["last_maintenance"] = {
        "ran_at" => Time.current.iso8601,
        "tasks" => results.keys,
        "success" => results.values.all? { |r| r[:success] }
      }

      instance.update!(config: config)
    end
  end
end
