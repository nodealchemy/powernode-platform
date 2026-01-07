# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TestEmailJob do
  let(:job) { described_class.new }
  let(:email_address) { 'test@example.com' }
  let(:account_id) { 'account_123' }
  let(:email_service) { instance_double(EmailConfigurationService) }
  let(:settings) do
    {
      smtp_host: 'smtp.example.com',
      smtp_port: 587,
      smtp_domain: 'example.com',
      smtp_username: 'user@example.com',
      smtp_password: 'password123',
      smtp_authentication: true,
      smtp_encryption: 'tls',
      smtp_from_address: 'noreply@example.com'
    }
  end

  before do
    allow(job).to receive(:logger).and_return(Logger.new(nil))
    allow(EmailConfigurationService).to receive(:instance).and_return(email_service)
    allow(email_service).to receive(:fetch_settings)
    allow(email_service).to receive(:settings).and_return(settings)
  end

  describe '#execute' do
    context 'with successful email delivery' do
      let(:mail_message) { instance_double(Mail::Message) }

      before do
        allow(Mail).to receive(:defaults)
        allow(Mail).to receive(:new).and_return(mail_message)
        allow(mail_message).to receive(:from)
        allow(mail_message).to receive(:to)
        allow(mail_message).to receive(:subject)
        allow(mail_message).to receive(:html_part)
        allow(mail_message).to receive(:text_part)
        allow(mail_message).to receive(:deliver!)
      end

      it 'refreshes email settings before sending' do
        expect(email_service).to receive(:fetch_settings).with(force_refresh: true)

        job.execute(email_address)
      end

      it 'configures mail delivery settings' do
        expect(Mail).to receive(:defaults)

        job.execute(email_address)
      end

      it 'sends the email' do
        expect(mail_message).to receive(:deliver!)

        job.execute(email_address)
      end

      it 'returns success result' do
        result = job.execute(email_address)

        expect(result[:success]).to be true
        expect(result[:email]).to eq(email_address)
        expect(result[:sent_at]).to be_present
      end

      it 'accepts optional account_id parameter' do
        result = job.execute(email_address, account_id)

        expect(result[:success]).to be true
      end
    end

    context 'when email settings refresh fails' do
      before do
        allow(email_service).to receive(:fetch_settings).and_raise(StandardError.new('API error'))

        # Still allow the email to be sent with cached settings
        mail_message = instance_double(Mail::Message)
        allow(Mail).to receive(:defaults)
        allow(Mail).to receive(:new).and_return(mail_message)
        allow(mail_message).to receive(:from)
        allow(mail_message).to receive(:to)
        allow(mail_message).to receive(:subject)
        allow(mail_message).to receive(:html_part)
        allow(mail_message).to receive(:text_part)
        allow(mail_message).to receive(:deliver!)
      end

      it 'continues with cached settings without raising error' do
        # Job should continue with cached settings even when refresh fails
        result = job.execute(email_address)
        expect(result[:success]).to be true
      end
    end

    context 'with SMTP authentication error' do
      before do
        allow(Mail).to receive(:defaults)
        mail_message = instance_double(Mail::Message)
        allow(Mail).to receive(:new).and_return(mail_message)
        allow(mail_message).to receive(:from)
        allow(mail_message).to receive(:to)
        allow(mail_message).to receive(:subject)
        allow(mail_message).to receive(:html_part)
        allow(mail_message).to receive(:text_part)
        allow(mail_message).to receive(:deliver!).and_raise(
          Net::SMTPAuthenticationError.new('535 Authentication failed')
        )
      end

      it 'raises descriptive error' do
        expect {
          job.execute(email_address)
        }.to raise_error(/SMTP authentication failed/)
      end
    end

    context 'with SMTP server busy error' do
      before do
        allow(Mail).to receive(:defaults)
        mail_message = instance_double(Mail::Message)
        allow(Mail).to receive(:new).and_return(mail_message)
        allow(mail_message).to receive(:from)
        allow(mail_message).to receive(:to)
        allow(mail_message).to receive(:subject)
        allow(mail_message).to receive(:html_part)
        allow(mail_message).to receive(:text_part)
        allow(mail_message).to receive(:deliver!).and_raise(
          Net::SMTPServerBusy.new('421 Too many connections')
        )
      end

      it 'raises descriptive error' do
        expect {
          job.execute(email_address)
        }.to raise_error(/SMTP server is busy/)
      end
    end

    context 'with connection timeout' do
      before do
        allow(Mail).to receive(:defaults)
        mail_message = instance_double(Mail::Message)
        allow(Mail).to receive(:new).and_return(mail_message)
        allow(mail_message).to receive(:from)
        allow(mail_message).to receive(:to)
        allow(mail_message).to receive(:subject)
        allow(mail_message).to receive(:html_part)
        allow(mail_message).to receive(:text_part)
        allow(mail_message).to receive(:deliver!).and_raise(
          Net::OpenTimeout.new('Connection timed out')
        )
      end

      it 'raises descriptive error' do
        expect {
          job.execute(email_address)
        }.to raise_error(/Could not connect to SMTP server/)
      end
    end

    context 'with generic error' do
      before do
        allow(Mail).to receive(:defaults)
        mail_message = instance_double(Mail::Message)
        allow(Mail).to receive(:new).and_return(mail_message)
        allow(mail_message).to receive(:from)
        allow(mail_message).to receive(:to)
        allow(mail_message).to receive(:subject)
        allow(mail_message).to receive(:html_part)
        allow(mail_message).to receive(:text_part)
        allow(mail_message).to receive(:deliver!).and_raise(
          StandardError.new('Unknown error')
        )
      end

      it 'raises wrapped error' do
        expect {
          job.execute(email_address)
        }.to raise_error(/Failed to send test email/)
      end
    end
  end

  describe 'job configuration' do
    it 'uses the email queue' do
      expect(described_class.sidekiq_options['queue']).to eq('email')
    end

    it 'retries once' do
      expect(described_class.sidekiq_options['retry']).to eq(1)
    end
  end
end
