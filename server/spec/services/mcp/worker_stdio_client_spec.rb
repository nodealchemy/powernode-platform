# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::WorkerStdioClient do
  let(:worker_url) { Rails.application.config.worker_url.chomp('/') }
  let(:account) { create(:account) }
  let(:server_hash) { { 'command' => 'node', 'args' => ['server.js'], 'env' => {}, 'capabilities' => {} } }
  let(:mcp_request) { { jsonrpc: '2.0', id: 'req-1', method: 'tools/call', params: {} } }

  before do
    allow(WorkerJobService).to receive(:system_worker_jwt).and_return('test-jwt')
  end

  describe '.execute' do
    it 'POSTs account_id/server/mcp_request and returns a symbolized result on success' do
      stub_request(:post, "#{worker_url}/api/v1/mcp/execute_stdio")
        .with(body: hash_including('account_id' => account.id, 'server' => server_hash))
        .to_return(status: 200, body: { 'result' => { 'output' => 'ok' } }.to_json)

      response = described_class.execute(account_id: account.id, server: server_hash, mcp_request: mcp_request, timeout: 12)

      expect(response).to eq(result: { output: 'ok' })
    end

    it "returns the worker's own error hash as-is, symbolized, on a domain-level failure" do
      stub_request(:post, "#{worker_url}/api/v1/mcp/execute_stdio")
        .to_return(status: 200, body: { 'error' => { 'message' => "Security error: 'foo' is not in the allowed list" } }.to_json)

      response = described_class.execute(account_id: account.id, server: server_hash, mcp_request: mcp_request, timeout: 12)

      expect(response).to eq(error: { message: "Security error: 'foo' is not in the allowed list" })
    end

    it 'lets a non-2xx worker response propagate as WorkerTransport::HttpError' do
      stub_request(:post, "#{worker_url}/api/v1/mcp/execute_stdio").to_return(status: 500, body: 'boom')

      expect do
        described_class.execute(account_id: account.id, server: server_hash, mcp_request: mcp_request, timeout: 12)
      end.to raise_error(WorkerTransport::HttpError)
    end

    it 'lets an unreachable worker propagate as WorkerTransport::ConnectionError' do
      stub_request(:post, "#{worker_url}/api/v1/mcp/execute_stdio").to_raise(Errno::ECONNREFUSED)

      expect do
        described_class.execute(account_id: account.id, server: server_hash, mcp_request: mcp_request, timeout: 12)
      end.to raise_error(WorkerTransport::ConnectionError)
    end

    it 'sends the per-call deadline to the worker as timeout_seconds' do
      stub_request(:post, "#{worker_url}/api/v1/mcp/execute_stdio")
        .with(body: hash_including('timeout_seconds' => 12))
        .to_return(status: 200, body: { 'result' => {} }.to_json)

      expect(described_class.execute(account_id: account.id, server: server_hash, mcp_request: mcp_request, timeout: 12))
        .to eq(result: {})
    end

    # IMP-abda86fb39be review — timeout ordering. The server must not give
    # up on the worker before the worker gives up on the child: otherwise
    # the Puma request fails with a generic "worker timeout" while the
    # worker's own child keeps running, hiding the real
    # StdioTimeoutError/process-failure/etc. message the worker would
    # otherwise have returned. Asserts against the REAL WorkerTransport
    # constructor call, not just the private #read_timeout number in
    # isolation, so a future refactor that stops passing it through still
    # fails this spec. IMP-f010c9fc7051: derived from the SAME per-call
    # timeout the worker is told to enforce, so the two cannot disagree.
    it 'sizes WorkerTransport.read_timeout from the passed timeout plus the TERM grace and margin' do
      expected = 12 + Mcp::SecurityService::STDIO_TERM_GRACE_SECONDS + described_class::READ_TIMEOUT_MARGIN_SECONDS

      expect(WorkerTransport).to receive(:new) do |**kwargs|
        expect(kwargs[:read_timeout]).to eq(expected)
        WorkerTransport.allocate.tap do |transport|
          allow(transport).to receive(:post).and_return('result' => {})
        end
      end

      described_class.execute(account_id: account.id, server: server_hash, mcp_request: mcp_request, timeout: 12)
    end
  end

  # IMP-f010c9fc7051 — the deadline is DB-driven config read per call (no
  # restart), falling back to the documented default when unset or
  # nonsensical, and never above the ceiling the worker enforces.
  describe '.timeout_seconds' do
    def stub_setting(value)
      allow(::SiteSetting).to receive(:get).and_call_original
      allow(::SiteSetting).to receive(:get).with(described_class::TIMEOUT_SETTING).and_return(value)
    end

    it 'defaults to DEFAULT_TIMEOUT_SECONDS when the setting is unset' do
      expect(described_class.timeout_seconds).to eq(described_class::DEFAULT_TIMEOUT_SECONDS)
    end

    it 'keeps the default below 30s (the worker async-job default), sized for a web request thread' do
      expect(described_class::DEFAULT_TIMEOUT_SECONDS).to be < 30
    end

    it 'honours a configured positive integer' do
      stub_setting(20)

      expect(described_class.timeout_seconds).to eq(20)
    end

    it 'reads a string-typed value as decimal, never octal' do
      stub_setting('010')

      expect(described_class.timeout_seconds).to eq(10)
    end

    [ 0, -5, 'abc', '20.5', 20.5, nil, true ].each do |bad|
      it "falls back to the default for #{bad.inspect}" do
        stub_setting(bad)

        expect(described_class.timeout_seconds).to eq(described_class::DEFAULT_TIMEOUT_SECONDS)
      end
    end

    it 'clamps a configured value above the worker ceiling to MAX_STDIO_TIMEOUT_SECONDS' do
      stub_setting(Mcp::SecurityService::MAX_STDIO_TIMEOUT_SECONDS + 10)

      expect(described_class.timeout_seconds).to eq(Mcp::SecurityService::MAX_STDIO_TIMEOUT_SECONDS)
    end

    it 'reads the real setting row, not a cached value' do
      SiteSetting.set(described_class::TIMEOUT_SETTING, '9', setting_type: 'integer')
      expect(described_class.timeout_seconds).to eq(9)

      SiteSetting.set(described_class::TIMEOUT_SETTING, '11', setting_type: 'integer')
      expect(described_class.timeout_seconds).to eq(11)
    end
  end
end
