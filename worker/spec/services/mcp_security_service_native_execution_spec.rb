# frozen_string_literal: true

require 'spec_helper'

# IMP-2c760325c102 (MCP isolation Phase 1 T4) — the native (unsandboxed)
# execution hatch and the spawn-time audit hooks on the worker side.
#   * `spawn_stdio(native_execution: true)` bypasses ONLY the sandbox: the
#     command/args/env it receives have already been through
#     #validate_stdio_server!, which is unchanged by the flag (see the
#     package-pinning spec for the proof that pinning still applies).
#   * Every refusal in #validate_stdio_server! and every native spawn is
#     reported through .audit_reporter — nil (no-op) in this suite, wired to
#     Mcp::SpawnAuditReporter by the worker at boot.
RSpec.describe McpSecurityService, 'native execution and spawn audit' do
  let(:reporter) { instance_double(Mcp::SpawnAuditReporter, spawn_refused: nil, native_execution_spawn: nil) }

  before do
    @previous_reporter = described_class.audit_reporter
    described_class.audit_reporter = reporter
  end

  after { described_class.audit_reporter = @previous_reporter }

  describe '.spawn_stdio(native_execution: true)' do
    let(:env) { { 'PATH' => ENV.fetch('PATH') } }

    it 'runs the child UNSANDBOXED even when the sandbox is required and unavailable, with a WARN and an audit row' do
      allow(described_class).to receive(:sandbox_available?).and_return(false)
      logger = described_class.send(:logger)
      expect(logger).to receive(:warn).with(/native execution.*UNSANDBOXED/i)
      expect(reporter).to receive(:native_execution_spawn)
        .with(mcp_server_id: 'srv-1', account_id: 'acct-1', sandbox_mode: 'required')

      with_sandbox_mode('required') do
        stdout, _stderr, status = described_class.spawn_stdio(
          '/bin/cat', env, [], stdin_data: 'ping', timeout: 5, mcp_server_id: 'srv-1', account_id: 'acct-1',
                            native_execution: true
        )
        expect(status.success?).to be true
        expect(stdout).to eq('ping')
      end
    end

    it 'never calls #sandbox_for_this_call? (the mode dispatch) when native execution is on' do
      expect(described_class).not_to receive(:sandbox_for_this_call?)

      with_sandbox_mode('required') do
        described_class.spawn_stdio('/bin/cat', env, [], stdin_data: '', timeout: 5, mcp_server_id: 'srv-1',
                                                       account_id: 'acct-1', native_execution: true)
      end
    end

    it 'still refuses (fail closed) without the flag when the sandbox is required and unavailable' do
      allow(described_class).to receive(:sandbox_available?).and_return(false)
      expect(reporter).not_to receive(:native_execution_spawn)

      with_sandbox_mode('required') do
        expect {
          described_class.spawn_stdio('/bin/cat', env, [], stdin_data: '', timeout: 5, mcp_server_id: 'srv-1', account_id: 'acct-1')
        }.to raise_error(described_class::SandboxUnavailableError)
      end
    end

    it 'does not audit an ordinary (non-native) spawn' do
      expect(reporter).not_to receive(:native_execution_spawn)

      described_class.spawn_stdio('/bin/cat', env, [], stdin_data: '', timeout: 5, mcp_server_id: 'srv-1', account_id: 'acct-1')
    end

    it 'a failing reporter never blocks the spawn' do
      allow(reporter).to receive(:native_execution_spawn).and_raise(StandardError, 'audit sink down')

      expect {
        described_class.spawn_stdio('/bin/cat', env, [], stdin_data: '', timeout: 5, mcp_server_id: 'srv-1',
                                                       account_id: 'acct-1', native_execution: true)
      }.not_to raise_error
    end
  end

  describe '.validate_stdio_server! refusal audit' do
    let(:server) { { 'id' => 'srv-1', 'account_id' => 'acct-1', 'command' => 'npx', 'args' => %w[-y pkg], 'env' => {}, 'capabilities' => {} } }

    it 'reports a refusal to the audit reporter and re-raises it unchanged' do
      expect(reporter).to receive(:spawn_refused).with(server, kind_of(described_class::CommandNotAllowedError))

      expect { described_class.validate_stdio_server!(server) }
        .to raise_error(described_class::CommandNotAllowedError, /not pinned/)
    end

    it 'reports an environment refusal too' do
      bad_env = server.merge('args' => %w[-y pkg@1.2.3], 'env' => { 'LD_PRELOAD' => '/tmp/x.so' })
      expect(reporter).to receive(:spawn_refused).with(bad_env, kind_of(described_class::EnvironmentViolationError))

      expect { described_class.validate_stdio_server!(bad_env) }.to raise_error(described_class::EnvironmentViolationError)
    end

    it 'does not report an accepted server' do
      expect(reporter).not_to receive(:spawn_refused)

      described_class.validate_stdio_server!(server.merge('args' => %w[-y pkg@1.2.3]))
    end

    it 'a failing reporter never changes the verdict' do
      allow(reporter).to receive(:spawn_refused).and_raise(StandardError, 'audit sink down')

      expect { described_class.validate_stdio_server!(server) }
        .to raise_error(described_class::CommandNotAllowedError, /not pinned/)
    end

    it 'is a no-op with no reporter configured (this suite\'s default)' do
      described_class.audit_reporter = nil

      expect { described_class.validate_stdio_server!(server) }
        .to raise_error(described_class::CommandNotAllowedError, /not pinned/)
    end
  end
end
