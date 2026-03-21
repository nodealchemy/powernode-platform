# frozen_string_literal: true

module System
  # Service for executing commands on node instances via SSH
  # Handles connection management, command execution, and error handling
  class SshExecutionService
    class SshError < StandardError; end

    # Execute a command on an instance
    #
    # @param instance [System::NodeInstance] The instance to execute on
    # @param command [String] The command to execute
    # @param sudo [Boolean] Whether to use sudo
    # @param operation_id [String, nil] Optional operation ID for tracking
    # @return [Hash] Result with :success, :stdout, :stderr, :exit_code, :error
    def self.execute(instance:, command:, sudo: true, operation_id: nil)
      new.execute(instance: instance, command: command, sudo: sudo, operation_id: operation_id)
    end

    # Sync instance state via SSH
    #
    # @param instance [System::NodeInstance] The instance to sync
    # @return [Hash] Result with :success, :error
    def self.sync(instance:)
      new.sync(instance: instance)
    end

    # Cleanse instance configuration via SSH
    #
    # @param instance [System::NodeInstance] The instance to cleanse
    # @return [Hash] Result with :success, :error
    def self.cleanse(instance:)
      new.cleanse(instance: instance)
    end

    def execute(instance:, command:, sudo: true, operation_id: nil)
      validate_instance!(instance)

      ssh_ip = instance.ssh_ip_address
      admin_user = instance.admin_user || "root"
      ssh_key = get_ssh_key(instance)

      unless ssh_ip.present?
        return { success: false, error: "No SSH IP address available", exit_code: -1 }
      end

      unless ssh_key.present?
        return { success: false, error: "No SSH key available", exit_code: -1 }
      end

      # Prepare command with sudo if requested
      full_command = sudo ? "sudo #{command}" : command

      Rails.logger.info("[SshExecutionService] Executing command on #{instance.name}: #{command[0..100]}...")

      begin
        result = execute_ssh_command(
          host: ssh_ip,
          user: admin_user,
          key: ssh_key,
          command: full_command
        )

        {
          success: result[:exit_code] == 0,
          stdout: result[:stdout],
          stderr: result[:stderr],
          exit_code: result[:exit_code]
        }
      rescue StandardError => e
        Rails.logger.error("[SshExecutionService] SSH execution failed: #{e.message}")
        { success: false, error: e.message, exit_code: -1 }
      end
    end

    def sync(instance:)
      validate_instance!(instance)

      node = instance.node
      platform = node&.node_template&.node_platform

      unless platform&.sync_script.present?
        return { success: true, message: "No sync script configured" }
      end

      # Execute sync script
      result = execute(
        instance: instance,
        command: "ipn sync",
        sudo: true
      )

      {
        success: result[:success],
        error: result[:error]
      }
    end

    def cleanse(instance:)
      validate_instance!(instance)

      # Execute cleanse command
      result = execute(
        instance: instance,
        command: "ipn cleanse",
        sudo: true
      )

      {
        success: result[:success],
        error: result[:error]
      }
    end

    private

    def validate_instance!(instance)
      raise ArgumentError, "Instance required" unless instance
      raise ArgumentError, "Instance must be a System::NodeInstance" unless instance.is_a?(::System::NodeInstance)
    end

    def get_ssh_key(instance)
      # First check instance-specific key
      return instance.key if instance.key.present?

      # Fall back to node SSH key
      instance.node&.ssh_key
    end

    def execute_ssh_command(host:, user:, key:, command:)
      # In production, this would use Net::SSH
      # For now, we'll implement a placeholder that can be replaced with real SSH
      #
      # Example with Net::SSH:
      # Net::SSH.start(host, user, key_data: [key], keys_only: true, timeout: 30) do |ssh|
      #   result = ssh.exec!(command)
      #   ...
      # end

      # Check if SSH is available and enabled
      unless ssh_available?
        Rails.logger.warn("[SshExecutionService] SSH not available - returning mock response")
        return mock_ssh_response(command)
      end

      # Execute via system SSH command (more portable than Net::SSH gem)
      require "open3"
      require "tempfile"

      key_file = Tempfile.new(["ssh_key", ".pem"])
      begin
        key_file.write(key)
        key_file.close
        File.chmod(0o600, key_file.path)

        ssh_options = [
          "-o", "StrictHostKeyChecking=no",
          "-o", "UserKnownHostsFile=/dev/null",
          "-o", "PasswordAuthentication=no",
          "-o", "ConnectTimeout=30",
          "-i", key_file.path
        ]

        ssh_command = ["ssh", *ssh_options, "#{user}@#{host}", command]

        stdout, stderr, status = Open3.capture3(*ssh_command)

        {
          stdout: stdout,
          stderr: stderr,
          exit_code: status.exitstatus
        }
      ensure
        key_file.unlink
      end
    end

    def ssh_available?
      # Check if SSH is enabled in the environment
      ENV["SYSTEM_SSH_ENABLED"] != "false"
    end

    def mock_ssh_response(command)
      Rails.logger.info("[SshExecutionService] Mock SSH execution: #{command}")
      {
        stdout: "Mock execution of: #{command}",
        stderr: "",
        exit_code: 0
      }
    end
  end
end
