# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::WebhookDeliveryJob, type: :job do
  let(:job_instance)      { described_class.new }
  let(:api_client_double) { double('BackendApiClient') }
  let(:delivery_id)       { 'delivery-uuid-1' }

  def delivery_response(webhook_url)
    {
      'success' => true,
      'data' => {
        'webhook_url' => webhook_url,
        'payload' => { 'event_type' => 'test', 'id' => 'x' },
        'headers' => {},
        'custom_headers' => {},
        'attempt' => 1,
        'endpoint_id' => 'endpoint-1',
        'circuit_broken' => false
      }
    }
  end

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    # mark_delivery_status / record_endpoint_result go through the API client.
    allow(api_client_double).to receive(:patch).and_return('success' => true)
    allow(api_client_double).to receive(:post).and_return('success' => true)
  end

  after { Sidekiq::Worker.clear_all }

  describe '#execute SSRF guard' do
    context 'when the webhook targets an internal address' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/webhook_deliveries/#{delivery_id}")
          .and_return(delivery_response('http://127.0.0.1:9000/admin'))
      end

      it 'blocks delivery and performs NO HTTP request' do
        expect(Net::HTTP).not_to receive(:new)

        job_instance.execute(delivery_id)
      end

      it 'marks the delivery failed with a blocked_ssrf category and never marks it in_progress' do
        allow(job_instance).to receive(:mark_delivery_status)

        result = job_instance.execute(delivery_id)

        expect(job_instance).to have_received(:mark_delivery_status)
          .with(delivery_id, 'failed', hash_including(error_category: 'blocked_ssrf'))
        expect(job_instance).not_to have_received(:mark_delivery_status)
          .with(delivery_id, 'in_progress')
        expect(result).to include(success: false, blocked: true)
      end

      it 'does not schedule a retry for a permanently-blocked URL' do
        job_instance.execute(delivery_id)

        expect(Webhooks::WebhookRetryJob.jobs).to be_empty
      end
    end

    context 'when the webhook targets a public host' do
      let(:webhook_url) { 'https://hooks.example.com/endpoint' }

      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/webhook_deliveries/#{delivery_id}")
          .and_return(delivery_response(webhook_url))
        allow(Resolv).to receive(:getaddresses).with('hooks.example.com').and_return(['93.184.216.34'])
        stub_request(:post, webhook_url).to_return(status: 200, body: 'ok')
      end

      it 'delivers the webhook and marks it delivered' do
        allow(job_instance).to receive(:mark_delivery_status)

        result = job_instance.execute(delivery_id)

        expect(job_instance).to have_received(:mark_delivery_status).with(delivery_id, 'in_progress')
        expect(job_instance).to have_received(:mark_delivery_status)
          .with(delivery_id, 'delivered', hash_including(status_code: 200))
        expect(result[:success]).to be(true)
        expect(a_request(:post, webhook_url)).to have_been_made.once
      end
    end
  end
end
