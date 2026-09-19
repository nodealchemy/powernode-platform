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
  def real_sandbox_available?
    Process.uid.zero? && !systemd_run_binary_path.nil?
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
