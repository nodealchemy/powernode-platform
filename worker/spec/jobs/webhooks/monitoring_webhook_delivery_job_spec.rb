# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::MonitoringWebhookDeliveryJob, type: :job do
  let(:job_instance) { described_class.new }
  let(:webhook_url)  { 'https://hooks.example.com/mcp' }
  let(:payload)      { { 'event_type' => 'tool_event', 'id' => 'abc' }.to_json }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after { Sidekiq::Worker.clear_all }

  describe '#execute' do
    context 'when the endpoint accepts the delivery' do
      before { stub_request(:post, webhook_url).to_return(status: 200, body: 'ok') }

      it 'POSTs the raw payload to the webhook URL and reports success' do
        result = job_instance.execute(webhook_url, payload)

        expect(a_request(:post, webhook_url).with(body: payload)).to have_been_made.once
        expect(result[:success]).to be(true)
        expect(result[:status_code]).to eq(200)
      end
    end

    context 'when the endpoint returns a non-2xx status' do
      before { stub_request(:post, webhook_url).to_return(status: 500, body: 'boom') }

      it 'raises so Sidekiq retries the delivery' do
        expect { job_instance.execute(webhook_url, payload) }
          .to raise_error(described_class::DeliveryError, /500/)
      end
    end
  end
end
