# frozen_string_literal: true

require 'rails_helper'

# Worker half of the alert / notification email path (Pattern B, mirrors
# Chat::AttachmentScanJob): deliver the mail via NotificationMailer, then POST
# the genuine outcome back to the server's internal ledger callback.
RSpec.describe Notifications::AlertEmailJob, type: :job do
  before do
    mock_powernode_worker_config
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow_logging_methods
  end

  let(:delivery_id) { SecureRandom.uuid }
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:callback_path) { "/api/v1/internal/emails/#{delivery_id}/delivered" }

  let(:payload) do
    {
      'email_delivery_id' => delivery_id,
      'recipient' => 'security@example.com',
      'subject' => 'Security Alert: suspicious_activity',
      'heading' => 'Security Alert',
      'body' => 'A security event was detected: suspicious_activity.',
      'details' => { 'ip_address' => '10.0.0.1', 'location' => 'Unknown' }
    }
  end

  let(:mailer) { double('NotificationMailer#alert_email') }
  let(:message) { double('Mail::Message', message_id: 'mid-123@mail') }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(api_client).to receive(:post)
    allow(NotificationMailer).to receive(:alert_email).and_return(mailer)
    allow(mailer).to receive(:deliver_now).and_return(message)
  end

  describe 'job configuration' do
    it 'uses the email queue with retry 3' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('email')
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe '#execute' do
    it 'validates required params' do
      expect { job.execute({}) }
        .to raise_error(ArgumentError, /Missing required parameters/)
    end

    it 'renders and delivers the alert email via NotificationMailer' do
      job.execute(payload)

      expect(NotificationMailer).to have_received(:alert_email).with(
        recipient: 'security@example.com',
        subject: 'Security Alert: suspicious_activity',
        heading: 'Security Alert',
        body: 'A security event was detected: suspicious_activity.',
        details: { 'ip_address' => '10.0.0.1', 'location' => 'Unknown' }
      )
      expect(mailer).to have_received(:deliver_now)
    end

    it 'reports the sent outcome (with message id) back to the server ledger' do
      expect(api_client).to receive(:post)
        .with(callback_path, hash_including(status: 'sent', message_id: 'mid-123@mail'))

      job.execute(payload)
    end

    context 'when SMTP delivery fails' do
      before do
        allow(mailer).to receive(:deliver_now)
          .and_raise(StandardError.new('SMTP connection refused'))
      end

      it 'records the failure on the ledger and re-raises for Sidekiq retry' do
        expect(api_client).to receive(:post)
          .with(callback_path, hash_including(status: 'failed', error: 'SMTP connection refused'))

        expect { job.execute(payload) }
          .to raise_error(StandardError, 'SMTP connection refused')
      end
    end
  end
end
