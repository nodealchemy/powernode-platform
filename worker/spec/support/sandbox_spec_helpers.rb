# frozen_string_literal: true

# IMP-a50680fd53d8 — support for specs that exercise the REAL stdio MCP
# sandbox (systemd-run + DynamicUser), which needs actual root privilege
# (see McpSecurityService's own comment for why there is no non-root
# path today). The default suite run sets MCP_STDIO_SANDBOX_MODE=off
# globally (see spec_helper.rb) so these never run unguarded; a spec that
# wants the REAL sandboxed path must check #real_sandbox_available? and
# skip with a clear message otherwise — never make the suite depend on
# root to pass.
module SandboxSpecHelpers
  # The real-systemd examples create transient units, dynamic users and
  # /var/cache directories on the host, so they need ALL of: an explicit
  # opt-in (MCP_SANDBOX_SYSTEMD_SPECS=1), root, systemd actually running as
  # the init system (a container with only the systemd-run binary would
  # FAIL, not skip), and systemd-run on PATH.
  #   sudo -n env "PATH=$PATH" MCP_SANDBOX_SYSTEMD_SPECS=1 bundle exec rspec \
  #     spec/services/mcp_security_service_spec.rb -e root-gated
  def real_sandbox_skip_reason
    return 'set MCP_SANDBOX_SYSTEMD_SPECS=1 to run the real-systemd sandbox examples' unless ENV['MCP_SANDBOX_SYSTEMD_SPECS'] == '1'
    return 'requires root (uid 0)' unless Process.uid.zero?
    return 'requires a booted systemd (/run/systemd/system) — not available in this environment' unless File.directory?('/run/systemd/system')
    return 'requires systemd-run on PATH' if systemd_run_binary_path.nil?

    nil
  end

  def real_sandbox_available?
    real_sandbox_skip_reason.nil?
  end

  def systemd_run_binary_path
    ENV['PATH'].to_s.split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'systemd-run') }
               .find { |path| File.executable?(path) }
  end

  # Temporarily overrides MCP_STDIO_SANDBOX_MODE for the duration of the
  # block, restoring the prior value (spec_helper's 'off') afterward —
  # never leaks into a later example.
  def with_sandbox_mode(mode)
    previous = ENV['MCP_STDIO_SANDBOX_MODE']
    ENV['MCP_STDIO_SANDBOX_MODE'] = mode
    yield
  ensure
    ENV['MCP_STDIO_SANDBOX_MODE'] = previous
  end
end

RSpec.configure do |config|
  config.include SandboxSpecHelpers
end
