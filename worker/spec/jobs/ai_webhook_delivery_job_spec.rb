# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWebhookDeliveryJob, type: :job do
  let(:job_instance)      { described_class.new }
  let(:api_client_double) { double('BackendApiClient') }
  let(:execution_id)      { 'exec-uuid-1' }

  def execution_response(webhook_urls)
    {
      'success' => true,
      'data' => {
        'webhook_urls' => webhook_urls,
        'agent_id' => 'agent-1',
        'status' => 'completed',
        'result' => { 'ok' => true },
        'completed_at' => Time.current.iso8601,
        'metadata' => {}
      }
    }
  end

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after { Sidekiq::Worker.clear_all }

  describe '#execute SSRF guard' do
    context 'when the webhook targets an internal address' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/ai/agent_executions/#{execution_id}")
          .and_return(execution_response(['http://169.254.169.254/latest/meta-data/']))
      end

      it 'blocks the delivery and performs NO HTTP request' do
        expect(Net::HTTP).not_to receive(:new)

        job_instance.execute(execution_id)
      end

      it 'records the blocked target as a failed delivery' do
        result = job_instance.execute(execution_id)

        expect(result[:webhooks_delivered]).to eq(0)
        expect(result[:webhooks_failed]).to eq(1)
        expect(result[:results].first).to include(success: false, blocked: true)
        expect(result[:results].first[:error]).to match(/Blocked SSRF target/)
      end
    end

    context 'when the webhook targets a public host' do
      let(:webhook_url) { 'https://hooks.example.com/endpoint' }

      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/ai/agent_executions/#{execution_id}")
          .and_return(execution_response([webhook_url]))
        # Public resolution so the guard permits delivery (no real DNS).
        allow(Resolv).to receive(:getaddresses).with('hooks.example.com').and_return(['93.184.216.34'])
        stub_request(:post, webhook_url).to_return(status: 200, body: 'ok')
      end

      it 'delivers the webhook' do
        result = job_instance.execute(execution_id)

        expect(result[:webhooks_delivered]).to eq(1)
        expect(result[:webhooks_failed]).to eq(0)
        expect(a_request(:post, webhook_url)).to have_been_made.once
      end
    end
  end
end
