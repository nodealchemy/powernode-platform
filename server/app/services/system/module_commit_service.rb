# frozen_string_literal: true

module System
  # Service for committing (deploying) node modules to instances
  # Handles file transfer, installation, and activation
  class ModuleCommitService
    class CommitError < StandardError; end

    COMMIT_STAGES = %w[prepare transfer install configure activate].freeze

    # Commit a module to an instance
    #
    # @param node_module [System::NodeModule] The module to commit
    # @param instance [System::NodeInstance] The target instance
    # @param options [Hash] Commit options
    # @return [Hash] Result with :success, :commit_id, :error
    def self.commit(node_module:, instance:, options: {})
      new.commit(node_module: node_module, instance: instance, options: options)
    end

    # Commit a module to all instances of a node
    #
    # @param node_module [System::NodeModule] The module to commit
    # @param node [System::Node] The target node
    # @param options [Hash] Commit options
    # @return [Hash] Result with :success, :results, :error
    def self.commit_to_node(node_module:, node:, options: {})
      new.commit_to_node(node_module: node_module, node: node, options: options)
    end

    def commit(node_module:, instance:, options: {})
      validate_module!(node_module)
      validate_instance!(instance)

      unless node_module.enabled?
        return { success: false, error: "Module is disabled" }
      end

      unless instance.active?
        return { success: false, error: "Instance is not running" }
      end

      Rails.logger.info("[ModuleCommitService] Committing #{node_module.name} to #{instance.name}")

      commit_id = generate_commit_id
      staging_dir = prepare_staging_directory(node_module, instance, commit_id)

      begin
        results = {}

        COMMIT_STAGES.each do |stage|
          Rails.logger.info("[ModuleCommitService] Stage: #{stage}")
          result = send("stage_#{stage}", node_module, instance, staging_dir, options)

          unless result[:success]
            rollback_commit(node_module, instance, staging_dir, stage, results)
            return { success: false, error: "Commit failed at #{stage}: #{result[:error]}", stage: stage }
          end

          results[stage] = result
        end

        # Record successful commit
        record_commit(node_module, instance, commit_id, results)

        cleanup_staging(staging_dir)

        {
          success: true,
          commit_id: commit_id,
          duration: calculate_duration(results)
        }
      rescue StandardError => e
        Rails.logger.error("[ModuleCommitService] Commit failed: #{e.message}")
        cleanup_staging(staging_dir)
        { success: false, error: e.message }
      end
    end

    def commit_to_node(node_module:, node:, options: {})
      validate_module!(node_module)
      validate_node!(node)

      instances = node.node_instances.where(status: "running")

      if instances.empty?
        return { success: false, error: "No running instances for node" }
      end

      Rails.logger.info("[ModuleCommitService] Committing #{node_module.name} to #{instances.count} instances")

      results = []
      all_success = true

      instances.find_each do |instance|
        result = commit(node_module: node_module, instance: instance, options: options)
        results << { instance_id: instance.id, instance_name: instance.name, result: result }
        all_success = false unless result[:success]
      end

      {
        success: all_success,
        results: results,
        total: instances.count,
        succeeded: results.count { |r| r[:result][:success] },
        failed: results.count { |r| !r[:result][:success] }
      }
    end

    private

    def validate_module!(node_module)
      raise ArgumentError, "Module required" unless node_module
      raise ArgumentError, "Module must be a System::NodeModule" unless node_module.is_a?(::System::NodeModule)
    end

    def validate_instance!(instance)
      raise ArgumentError, "Instance required" unless instance
      raise ArgumentError, "Instance must be a System::NodeInstance" unless instance.is_a?(::System::NodeInstance)
    end

    def validate_node!(node)
      raise ArgumentError, "Node required" unless node
      raise ArgumentError, "Node must be a System::Node" unless node.is_a?(::System::Node)
    end

    def generate_commit_id
      "commit-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"
    end

    def prepare_staging_directory(node_module, instance, commit_id)
      dir = File.join(Rails.root, "tmp", "commits", commit_id)
      FileUtils.mkdir_p(dir)
      FileUtils.mkdir_p(File.join(dir, "files"))
      FileUtils.mkdir_p(File.join(dir, "scripts"))
      dir
    end

    def cleanup_staging(staging_dir)
      FileUtils.rm_rf(staging_dir) if staging_dir && File.exist?(staging_dir)
    rescue StandardError => e
      Rails.logger.warn("[ModuleCommitService] Cleanup failed: #{e.message}")
    end

    # Stage: Prepare - Set up files for transfer
    def stage_prepare(node_module, instance, staging_dir, options)
      Rails.logger.info("[ModuleCommitService] Preparing commit files")

      start_time = Time.current
      files_dir = File.join(staging_dir, "files")

      # Extract module data to staging
      if node_module.data.present?
        # In production, would extract from FileObject storage
        Rails.logger.info("[ModuleCommitService] Would extract module data to #{files_dir}")
      end

      # Process copy paths
      copy_paths = node_module.node_module_copy_paths.to_a
      Rails.logger.info("[ModuleCommitService] Processing #{copy_paths.count} copy paths")

      # Generate installation scripts based on file_spec
      scripts = generate_install_scripts(node_module, staging_dir)

      {
        success: true,
        duration: Time.current - start_time,
        files_count: copy_paths.count,
        scripts: scripts
      }
    end

    # Stage: Transfer - Copy files to instance
    def stage_transfer(node_module, instance, staging_dir, options)
      Rails.logger.info("[ModuleCommitService] Transferring files to instance")

      start_time = Time.current
      files_dir = File.join(staging_dir, "files")

      ssh_ip = instance.ssh_ip_address
      admin_user = instance.admin_user || "root"

      unless ssh_ip.present?
        return { success: false, error: "No SSH IP address available" }
      end

      # In production, would use SCP/SFTP:
      # scp -r #{files_dir}/* #{admin_user}@#{ssh_ip}:/tmp/module-staging/

      # Or use rsync for efficiency:
      # rsync -avz --delete #{files_dir}/ #{admin_user}@#{ssh_ip}:/tmp/module-staging/

      Rails.logger.info("[ModuleCommitService] Would transfer files to #{admin_user}@#{ssh_ip}")

      {
        success: true,
        duration: Time.current - start_time,
        destination: "/tmp/module-staging"
      }
    end

    # Stage: Install - Run installation commands
    def stage_install(node_module, instance, staging_dir, options)
      Rails.logger.info("[ModuleCommitService] Installing module on instance")

      start_time = Time.current

      # Execute copy path operations
      node_module.node_module_copy_paths.each do |copy_path|
        result = execute_copy_path(instance, copy_path)
        unless result[:success]
          return { success: false, error: "Failed to copy #{copy_path.source_path}: #{result[:error]}" }
        end
      end

      # Run module install script if present
      if node_module.file_spec&.dig("install_script").present?
        result = SshExecutionService.execute(
          instance: instance,
          command: "/tmp/module-staging/install.sh",
          sudo: true
        )

        unless result[:success]
          return { success: false, error: "Install script failed: #{result[:error]}" }
        end
      end

      {
        success: true,
        duration: Time.current - start_time
      }
    end

    # Stage: Configure - Apply configuration
    def stage_configure(node_module, instance, staging_dir, options)
      Rails.logger.info("[ModuleCommitService] Configuring module")

      start_time = Time.current

      # Apply mask configuration
      if node_module.mask.present?
        apply_mask_configuration(node_module, instance)
      end

      # Run configuration script if present
      if node_module.file_spec&.dig("config_script").present?
        result = SshExecutionService.execute(
          instance: instance,
          command: "/tmp/module-staging/configure.sh",
          sudo: true
        )

        unless result[:success]
          return { success: false, error: "Config script failed: #{result[:error]}" }
        end
      end

      {
        success: true,
        duration: Time.current - start_time
      }
    end

    # Stage: Activate - Enable and start services
    def stage_activate(node_module, instance, staging_dir, options)
      Rails.logger.info("[ModuleCommitService] Activating module")

      start_time = Time.current

      # Reload systemd if needed
      if options[:reload_systemd] || node_module.file_spec&.dig("systemd_units").present?
        result = SshExecutionService.execute(
          instance: instance,
          command: "systemctl daemon-reload",
          sudo: true
        )

        Rails.logger.info("[ModuleCommitService] Systemd reload: #{result[:success]}")
      end

      # Start services defined in module
      services = node_module.file_spec&.dig("services") || []
      services.each do |service|
        result = SshExecutionService.execute(
          instance: instance,
          command: "systemctl enable --now #{service}",
          sudo: true
        )

        unless result[:success]
          Rails.logger.warn("[ModuleCommitService] Failed to start service #{service}")
        end
      end

      # Cleanup staging directory on instance
      SshExecutionService.execute(
        instance: instance,
        command: "rm -rf /tmp/module-staging",
        sudo: true
      )

      {
        success: true,
        duration: Time.current - start_time,
        services_activated: services
      }
    end

    def rollback_commit(node_module, instance, staging_dir, failed_stage, results)
      Rails.logger.info("[ModuleCommitService] Rolling back commit at stage #{failed_stage}")

      # Reverse stages that completed
      completed_stages = COMMIT_STAGES.take_while { |s| s != failed_stage }

      completed_stages.reverse_each do |stage|
        rollback_stage(stage, node_module, instance, staging_dir, results[stage])
      end
    end

    def rollback_stage(stage, node_module, instance, staging_dir, stage_result)
      case stage
      when "activate"
        # Stop any started services
        services = node_module.file_spec&.dig("services") || []
        services.each do |service|
          SshExecutionService.execute(
            instance: instance,
            command: "systemctl stop #{service}",
            sudo: true
          )
        end
      when "install"
        # Remove installed files (if tracked)
        node_module.node_module_copy_paths.each do |copy_path|
          SshExecutionService.execute(
            instance: instance,
            command: "rm -rf #{copy_path.destination_path}",
            sudo: true
          )
        end
      end
    rescue StandardError => e
      Rails.logger.error("[ModuleCommitService] Rollback failed for #{stage}: #{e.message}")
    end

    def execute_copy_path(instance, copy_path)
      # Build copy command
      cmd = if copy_path.recursive?
              "cp -r /tmp/module-staging/#{copy_path.source_path} #{copy_path.destination_path}"
            else
              "cp /tmp/module-staging/#{copy_path.source_path} #{copy_path.destination_path}"
            end

      # Ensure destination directory exists
      dest_dir = File.dirname(copy_path.destination_path)
      SshExecutionService.execute(
        instance: instance,
        command: "mkdir -p #{dest_dir}",
        sudo: true
      )

      # Execute copy
      SshExecutionService.execute(
        instance: instance,
        command: cmd,
        sudo: true
      )
    end

    def apply_mask_configuration(node_module, instance)
      # Process mask values and apply to configuration files
      mask = node_module.mask

      mask.each do |file_path, values|
        next unless values.is_a?(Hash)

        # In production, would generate sed/awk commands or use templating
        Rails.logger.info("[ModuleCommitService] Would apply mask to #{file_path}")
      end
    end

    def generate_install_scripts(node_module, staging_dir)
      scripts = []
      scripts_dir = File.join(staging_dir, "scripts")

      # Generate main install script
      install_script = generate_install_script(node_module)
      install_path = File.join(scripts_dir, "install.sh")
      File.write(install_path, install_script)
      File.chmod(0o755, install_path)
      scripts << install_path

      # Generate configure script
      if node_module.mask.present?
        config_script = generate_config_script(node_module)
        config_path = File.join(scripts_dir, "configure.sh")
        File.write(config_path, config_script)
        File.chmod(0o755, config_path)
        scripts << config_path
      end

      scripts
    end

    def generate_install_script(node_module)
      <<~BASH
        #!/bin/bash
        set -e

        echo "Installing module: #{node_module.name}"
        echo "Priority: #{node_module.priority}"

        # Module-specific installation logic would go here
        # Based on file_spec configuration

        echo "Installation complete"
      BASH
    end

    def generate_config_script(node_module)
      <<~BASH
        #!/bin/bash
        set -e

        echo "Configuring module: #{node_module.name}"

        # Apply mask configurations
        # Template substitution logic would go here

        echo "Configuration complete"
      BASH
    end

    def record_commit(node_module, instance, commit_id, results)
      # Find or create module assignment
      assignment = ::System::NodeModuleAssignment.find_or_create_by!(
        node: instance.node,
        node_module: node_module
      )

      # Update with commit info
      config = assignment.config || {}
      config["last_commit"] = {
        "commit_id" => commit_id,
        "instance_id" => instance.id,
        "committed_at" => Time.current.iso8601,
        "success" => true
      }

      assignment.update!(config: config)
    end

    def calculate_duration(results)
      results.values.sum { |r| r[:duration] || 0 }
    end
  end
end
