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

      response = described_class.execute(account_id: account.id, server: server_hash, mcp_request: mcp_request)

      expect(response).to eq(result: { output: 'ok' })
    end

    it "returns the worker's own error hash as-is, symbolized, on a domain-level failure" do
      stub_request(:post, "#{worker_url}/api/v1/mcp/execute_stdio")
        .to_return(status: 200, body: { 'error' => { 'message' => "Security error: 'foo' is not in the allowed list" } }.to_json)

      response = described_class.execute(account_id: account.id, server: server_hash, mcp_request: mcp_request)

      expect(response).to eq(error: { message: "Security error: 'foo' is not in the allowed list" })
    end

    it 'lets a non-2xx worker response propagate as WorkerTransport::HttpError' do
      stub_request(:post, "#{worker_url}/api/v1/mcp/execute_stdio").to_return(status: 500, body: 'boom')

      expect do
        described_class.execute(account_id: account.id, server: server_hash, mcp_request: mcp_request)
      end.to raise_error(WorkerTransport::HttpError)
    end

    it 'lets an unreachable worker propagate as WorkerTransport::ConnectionError' do
      stub_request(:post, "#{worker_url}/api/v1/mcp/execute_stdio").to_raise(Errno::ECONNREFUSED)

      expect do
        described_class.execute(account_id: account.id, server: server_hash, mcp_request: mcp_request)
      end.to raise_error(WorkerTransport::ConnectionError)
    end

    # IMP-abda86fb39be review — timeout ordering. The server must not give
    # up on the worker before the worker gives up on the child: otherwise
    # the Puma request fails with a generic "worker timeout" while the
    # worker's own child keeps running, hiding the real
    # StdioTimeoutError/process-failure/etc. message the worker would
    # otherwise have returned. Asserts against the REAL WorkerTransport
    # constructor call, not just the private #read_timeout number in
    # isolation, so a future refactor that stops passing it through still
    # fails this spec.
    it 'sizes WorkerTransport.read_timeout to outlast the worker deadline plus its TERM grace' do
      stdio_timeout = Mcp::SecurityService.stdio_timeout_seconds
      grace = Mcp::SecurityService::STDIO_TERM_GRACE_SECONDS

      expect(WorkerTransport).to receive(:new) do |**kwargs|
        expect(kwargs[:read_timeout]).to be > stdio_timeout + grace
        WorkerTransport.allocate.tap do |transport|
          allow(transport).to receive(:post).and_return('result' => {})
        end
      end

      described_class.execute(account_id: account.id, server: server_hash, mcp_request: mcp_request)
    end
  end
end
