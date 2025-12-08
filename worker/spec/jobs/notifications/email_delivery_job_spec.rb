# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../app/services/email_delivery_worker_service'

RSpec.describe Notifications::EmailDeliveryJob, type: :job do
  subject { described_class }

  let(:email_data) do
    {
      'to' => 'recipient@example.com',
      'subject' => 'Test Email Subject',
      'body' => 'Test email body content',
      'email_type' => 'notification',
      'account_id' => 'account-123',
      'user_id' => 'user-456',
      'template' => 'notification_template',
      'template_data' => { 'name' => 'John Doe', 'action' => 'test' },
      'from' => 'noreply@powernode.com',
      'reply_to' => 'support@powernode.com',
      'content_type' => 'html',
      'attachments' => []
    }
  end

  let(:email_service_double) { double('EmailDeliveryWorkerService') }
  let(:job_instance) { subject.new }

  before do
    mock_powernode_worker_config
    allow(EmailDeliveryWorkerService).to receive(:new).and_return(email_service_double)
  end

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with parameter validation', ['to', 'subject', 'body', 'email_type']
  it_behaves_like 'a job with logging'
  it_behaves_like 'a job with timing metrics'

  describe 'job configuration' do
    it 'uses email queue' do
      expect(subject.sidekiq_options['queue']).to eq('email')
    end

    it 'has retry count of 3' do
      expect(subject.sidekiq_options['retry']).to eq(3)
    end

    it 'includes backtrace on failure' do
      expect(subject.sidekiq_options['backtrace']).to be true
    end
  end

  describe '#execute' do
    context 'with valid email data' do
      before do
        allow(email_service_double).to receive(:send_email).and_return({
          success: true,
          data: { delivery_id: 'delivery-123', status: 'sent' }
        })
      end

      it 'processes email delivery successfully' do
        result = job_instance.execute(email_data)
        
        expect(result[:success]).to be true
        expect(result.dig(:data, :delivery_id)).to eq('delivery-123')
      end

      it 'calls email service with correct parameters' do
        job_instance.execute(email_data)
        
        expect(email_service_double).to have_received(:send_email).with({
          to: 'recipient@example.com',
          subject: 'Test Email Subject',
          body: 'Test email body content',
          email_type: 'notification',
          account_id: 'account-123',
          user_id: 'user-456',
          template: 'notification_template',
          template_data: { 'name' => 'John Doe', 'action' => 'test' },
          from: 'noreply@powernode.com',
          reply_to: 'support@powernode.com',
          content_type: 'html',
          attachments: []
        })
      end

      it 'handles missing optional parameters' do
        minimal_data = email_data.slice('to', 'subject', 'body', 'email_type')
        
        job_instance.execute(minimal_data)
        
        expect(email_service_double).to have_received(:send_email).with(
          hash_including(
            to: 'recipient@example.com',
            subject: 'Test Email Subject',
            body: 'Test email body content',
            email_type: 'notification',
            template_data: {}
          )
        )
      end

      it 'logs successful processing' do
        logger_double = mock_logger
        
        job_instance.execute(email_data)
        
        # Check that both log messages were called (order may vary)
        expect(logger_double).to have_received(:info).with(
          a_string_matching(/Processing email delivery job/)
        )
        
        expect(logger_double).to have_received(:info).with(
          a_string_matching(/Email delivery job completed successfully/)
        )
      end
    end

    context 'with invalid email data' do
      it 'raises error for missing required parameters' do
        invalid_data = email_data.except('subject')
        
        expect {
          job_instance.execute(invalid_data)
        }.to raise_error(ArgumentError, /Missing required parameters: subject/)
      end

      it 'validates all required parameters' do
        empty_data = {}
        
        expect {
          job_instance.execute(empty_data)
        }.to raise_error(ArgumentError, /Missing required parameters: to, subject, body, email_type/)
      end
    end

    context 'when email service fails' do
      before do
        allow(email_service_double).to receive(:send_email).and_return({
          success: false,
          error: 'SMTP server unavailable'
        })
      end

      it 'logs failure and returns error result' do
        logger_double = mock_logger
        
        result = job_instance.execute(email_data)
        
        expect(result[:success]).to be false
        expect(result[:error]).to eq('SMTP server unavailable')
        
        expect(logger_double).to have_received(:error).with(
          a_string_matching(/Email delivery job failed/)
        )
      end

      it 'still returns the service result' do
        result = job_instance.execute(email_data)
        
        expect(result).to eq({
          success: false,
          error: 'SMTP server unavailable'
        })
      end
    end

    context 'when email service raises exception' do
      before do
        allow(email_service_double).to receive(:send_email)
          .and_raise(StandardError.new('Service connection error'))
      end

      it 'allows exception to bubble up' do
        expect {
          job_instance.execute(email_data)
        }.to raise_error(StandardError, 'Service connection error')
      end
    end

    context 'with different email types' do
      let(:welcome_email_data) do
        email_data.merge({
          'email_type' => 'welcome',
          'template' => 'welcome_template'
        })
      end

      let(:password_reset_data) do
        email_data.merge({
          'email_type' => 'password_reset',
          'template' => 'password_reset_template',
          'template_data' => { 'reset_token' => 'token123', 'expires_at' => '2024-01-15T10:00:00Z' }
        })
      end

      before do
        allow(email_service_double).to receive(:send_email).and_return({
          success: true,
          data: { delivery_id: 'delivery-456' }
        })
      end

      it 'handles welcome emails' do
        result = job_instance.execute(welcome_email_data)
        
        expect(result[:success]).to be true
        expect(email_service_double).to have_received(:send_email).with(
          hash_including(
            email_type: 'welcome',
            template: 'welcome_template'
          )
        )
      end

      it 'handles password reset emails' do
        result = job_instance.execute(password_reset_data)
        
        expect(result[:success]).to be true
        expect(email_service_double).to have_received(:send_email).with(
          hash_including(
            email_type: 'password_reset',
            template: 'password_reset_template',
            template_data: { 'reset_token' => 'token123', 'expires_at' => '2024-01-15T10:00:00Z' }
          )
        )
      end
    end

    context 'with attachments' do
      let(:email_with_attachments) do
        email_data.merge({
          'attachments' => [
            { 'filename' => 'report.pdf', 'content_type' => 'application/pdf', 'data' => 'base64_data' },
            { 'filename' => 'invoice.xlsx', 'content_type' => 'application/xlsx', 'path' => '/tmp/invoice.xlsx' }
          ]
        })
      end

      before do
        allow(email_service_double).to receive(:send_email).and_return({
          success: true,
          data: { delivery_id: 'delivery-789', attachments_processed: 2 }
        })
      end

      it 'processes emails with attachments' do
        result = job_instance.execute(email_with_attachments)
        
        expect(result[:success]).to be true
        expect(email_service_double).to have_received(:send_email).with(
          hash_including(
            attachments: [
              { 'filename' => 'report.pdf', 'content_type' => 'application/pdf', 'data' => 'base64_data' },
              { 'filename' => 'invoice.xlsx', 'content_type' => 'application/xlsx', 'path' => '/tmp/invoice.xlsx' }
            ]
          )
        )
      end
    end
  end

  describe 'integration with Sidekiq' do
    it 'can be enqueued' do
      with_sidekiq_testing_mode(:fake) do
        described_class.perform_async(email_data)
        
        expect(described_class.jobs.size).to eq(1)
        expect(described_class.jobs.first['args']).to eq([email_data])
      end
    end

    it 'uses correct queue' do
      with_sidekiq_testing_mode(:fake) do
        described_class.perform_async(email_data)
        
        expect_job_in_queue(described_class, 'email')
      end
    end

    it 'processes job inline when configured' do
      allow(EmailDeliveryWorkerService).to receive(:new).and_return(email_service_double)
      allow(email_service_double).to receive(:send_email).and_return({ success: true })
      # Disable runaway loop protection for inline testing
      allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)

      with_sidekiq_testing_mode(:inline) do
        described_class.perform_async(email_data)

        expect(email_service_double).to have_received(:send_email)
      end
    end
  end

  describe 'error scenarios and retry behavior' do
    let(:retryable_error) { StandardError.new('Temporary email service error') }
    let(:non_retryable_error) { ArgumentError.new('Invalid email format') }

    it 'allows retries for retryable errors' do
      allow(email_service_double).to receive(:send_email).and_raise(retryable_error)
      
      with_sidekiq_testing_mode(:fake) do
        described_class.perform_async(email_data)
        
        # In fake mode, jobs that fail are not automatically retried
        # We can verify the job was enqueued and will be configured for retry
        expect(described_class.jobs.size).to eq(1)
        expect(described_class.sidekiq_options['retry']).to be > 0
        
        # Verify job fails when executed due to the error
        expect {
          described_class.drain
        }.to raise_error(retryable_error.class)
      end
    end

    it 'uses custom retry logic from BaseJob' do
      retry_intervals = []
      
      # Mock Sidekiq retry mechanism
      allow_any_instance_of(described_class).to receive(:perform) do
        retry_intervals << described_class.sidekiq_retry_in_block.call(retry_intervals.size + 1, retryable_error)
        raise retryable_error if retry_intervals.size <= 3
      end
      
      begin
        job_instance.perform(email_data)
      rescue StandardError
        # Expected after retries
      end
      
      expect(retry_intervals).not_to be_empty
    end
  end
end