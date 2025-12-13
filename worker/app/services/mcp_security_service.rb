# frozen_string_literal: true

# Service for MCP security hardening in worker
# Provides command whitelist validation and environment sanitization
# Mirror of server/app/services/mcp_security_service.rb
class McpSecurityService
  class SecurityError < StandardError; end
  class CommandNotAllowedError < SecurityError; end
  class EnvironmentViolationError < SecurityError; end

  # Allowed commands for stdio MCP servers
  ALLOWED_COMMANDS = %w[
    npx
    node
    python
    python3
    ruby
    deno
    bun
    /usr/bin/env
    /usr/bin/node
    /usr/bin/python
    /usr/bin/python3
    /usr/bin/ruby
    /usr/local/bin/node
    /usr/local/bin/npx
    /usr/local/bin/python
    /usr/local/bin/python3
    /usr/local/bin/ruby
    /usr/local/bin/deno
    /usr/local/bin/bun
  ].freeze

  # Extended commands enabled by configuration
  EXTENDED_COMMANDS = %w[
    uvx
    uv
    pipx
    docker
    podman
    java
    dotnet
    go
  ].freeze

  # Allowed environment variable prefixes
  ALLOWED_ENV_PREFIXES = %w[
    MCP_
    OPENAI_
    ANTHROPIC_
    GOOGLE_
    AZURE_
    AWS_
    GCP_
    HUGGING_FACE_
    COHERE_
    MISTRAL_
    PERPLEXITY_
  ].freeze

  # Explicitly allowed environment variables
  ALLOWED_ENV_VARS = %w[
    PATH
    HOME
    USER
    LANG
    LC_ALL
    LC_CTYPE
    TERM
    TZ
    NODE_ENV
    PYTHON_PATH
    PYTHONPATH
    RUBY_VERSION
    GEM_HOME
    GEM_PATH
    BUNDLE_PATH
    XDG_CONFIG_HOME
    XDG_DATA_HOME
    XDG_CACHE_HOME
    TMPDIR
    TEMP
    TMP
  ].freeze

  # Forbidden environment variables (security sensitive)
  FORBIDDEN_ENV_VARS = %w[
    LD_PRELOAD
    LD_LIBRARY_PATH
    DYLD_INSERT_LIBRARIES
    DYLD_LIBRARY_PATH
    RUBYOPT
    PYTHONSTARTUP
    NODE_OPTIONS
    BASH_ENV
    ENV
    CDPATH
  ].freeze

  class << self
    # Validate a command against the whitelist
    def validate_command!(command, allow_extended: false)
      return if command.blank?

      base_command = extract_base_command(command)
      allowed = allowed_commands(allow_extended)

      unless base_command_in_allowed_list?(base_command, allowed)
        raise CommandNotAllowedError,
              "Command '#{base_command}' is not in the allowed list. " \
              "Allowed commands: #{allowed.join(', ')}"
      end

      validate_command_arguments!(command)
    end

    # Check if a command is allowed (without raising)
    def command_allowed?(command, allow_extended: false)
      base_command = extract_base_command(command)
      allowed = allow_extended ? (ALLOWED_COMMANDS + EXTENDED_COMMANDS) : ALLOWED_COMMANDS

      allowed.any? do |allowed_cmd|
        base_command == allowed_cmd ||
          base_command.end_with?("/#{allowed_cmd}") ||
          File.basename(base_command) == allowed_cmd
      end
    end

    # Sanitize environment variables
    def sanitize_environment(env, strict: false)
      return {} if env.blank?

      env.transform_keys(&:to_s).select do |key, _value|
        env_allowed?(key, strict: strict)
      end
    end

    # Check if an environment variable is allowed
    def env_allowed?(key, strict: false)
      key = key.to_s.upcase

      return false if FORBIDDEN_ENV_VARS.include?(key)
      return true if ALLOWED_ENV_PREFIXES.any? { |prefix| key.start_with?(prefix) }
      return true if ALLOWED_ENV_VARS.include?(key)

      !strict
    end

    # Validate environment and raise if forbidden vars present
    def validate_environment!(env)
      return if env.blank?

      forbidden = env.keys.map(&:to_s).map(&:upcase) & FORBIDDEN_ENV_VARS

      return unless forbidden.any?

      raise EnvironmentViolationError,
            "Forbidden environment variables detected: #{forbidden.join(', ')}. " \
            'These variables could be used for code injection.'
    end

    # Full security validation for stdio execution
    def validate_stdio_execution!(command:, env:, allow_extended: false, strict_env: false)
      validate_command!(command, allow_extended: allow_extended)
      validate_environment!(env) if env.present?

      { command: command, env: sanitize_environment(env, strict: strict_env) }
    end

    private

    def extract_base_command(command)
      return '' if command.blank?

      parts = command.to_s.strip.split(/\s+/)
      first_part = parts.first.to_s

      if first_part == 'env' || first_part.end_with?('/env')
        parts.drop(1).find { |p| !p.include?('=') } || first_part
      else
        first_part
      end
    end

    def allowed_commands(allow_extended)
      allow_extended ? (ALLOWED_COMMANDS + EXTENDED_COMMANDS) : ALLOWED_COMMANDS
    end

    # Check if base command is in the allowed list
    def base_command_in_allowed_list?(base_command, allowed)
      allowed.any? do |allowed_cmd|
        base_command == allowed_cmd ||
          base_command.end_with?("/#{allowed_cmd}") ||
          File.basename(base_command) == allowed_cmd
      end
    end

    def validate_command_arguments!(command)
      dangerous_patterns = [
        /[;&|`$]/,
        /\$\(/,
        /\$\{/,
        %r{>\s*/},
        %r{<\s*/},
        /\|\s*\w+/,
        /\beval\b/,
        /\bexec\b/,
        /\bsource\b/,
        %r{\.\s*/}
      ]

      args_portion = command.to_s.split(/\s+/, 2)[1].to_s

      dangerous_patterns.each do |pattern|
        if args_portion.match?(pattern)
          raise CommandNotAllowedError,
                "Potentially dangerous pattern detected in command arguments: #{pattern.source}"
        end
      end
    end
  end
end
