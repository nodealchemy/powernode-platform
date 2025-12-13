# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../app/jobs/test_email_job'

RSpec.describe TestEmailJob do
  let(:email_address) { 'test@example.com' }
  let(:account_id) { 'account_123' }

  before do
    # Clear any previous emails
    ActionMailer::Base.deliveries.clear
    
    # Mock logger to prevent output during tests
    allow_any_instance_of(TestEmailJob).to receive(:logger).and_return(
      instance_double('Logger', info: nil, warn: nil, error: nil, level: Logger::INFO)
    )
  end

  describe '#execute' do
    context 'in test environment' do
      before do
        allow(PowernodeWorker.application).to receive(:env).and_return('test')
      end

      it 'simulates email delivery without sending actual email' do
        job = TestEmailJob.new
        
        expect {
          job.execute(email_address, account_id)
        }.not_to raise_error
        
        # In test environment, no actual email should be delivered
        expect(ActionMailer::Base.deliveries).to be_empty
      end

      it 'handles hash format parameters' do
        job = TestEmailJob.new
        hash_params = {
          'email' => email_address,
          'account_id' => account_id
        }
        
        expect {
          job.execute(hash_params)
        }.not_to raise_error
      end

      it 'handles missing email address gracefully' do
        job = TestEmailJob.new
        
        expect {
          job.execute(nil)
        }.not_to raise_error
      end

      it 'logs appropriate messages for test environment' do
        logger = instance_double('Logger')
        allow_any_instance_of(TestEmailJob).to receive(:logger).and_return(logger)
        
        # Allow all log messages to be flexible since the job logs multiple things
        allow(logger).to receive(:info)
        allow(logger).to receive(:warn)
        allow(logger).to receive(:error)
        allow(logger).to receive(:level).and_return(Logger::INFO)
        
        # Verify specific key messages are logged
        expect(logger).to receive(:info).with(/Sending test email to configured recipient/)
        expect(logger).to receive(:info).with(/Test environment detected/)
        expect(logger).to receive(:info).with(/Test email would be sent to/)
        expect(logger).to receive(:info).with(/Email delivery simulation completed/)
        
        job = TestEmailJob.new
        job.execute(email_address, account_id)
      end
    end

    context 'in development environment' do
      before do
        allow(PowernodeWorker.application).to receive(:env).and_return('development')
        
        # Mock EmailConfigurationService
        email_service = instance_double('EmailConfigurationService')
        allow(EmailConfigurationService).to receive(:instance).and_return(email_service)
        allow(email_service).to receive(:fetch_settings)
        allow(email_service).to receive(:settings).and_return({ provider: 'smtp' })
        
        # Mock NotificationMailer
        mailer = instance_double('ActionMailer::MessageDelivery')
        allow(NotificationMailer).to receive(:test_email).and_return(mailer)
        allow(mailer).to receive(:deliver_now)
      end

      it 'attempts to send real email in development' do
        job = TestEmailJob.new
        
        expect(EmailConfigurationService.instance).to receive(:fetch_settings)
        expect(NotificationMailer).to receive(:test_email).with(email_address)
        
        job.execute(email_address, account_id)
      end
    end

    context 'audit logging' do
      let(:api_client) { instance_double('ApiClient') }
      
      before do
        allow(PowernodeWorker.application).to receive(:env).and_return('test')
        allow_any_instance_of(TestEmailJob).to receive(:api_client).and_return(api_client)
        allow(api_client).to receive(:post)
        
        # Mock SystemWorkerAuth
        system_auth = instance_double('SystemWorkerAuth')
        allow(SystemWorkerAuth).to receive(:instance).and_return(system_auth)
        allow(system_auth).to receive(:create_api_client).and_return(api_client)
        
        # Mock EmailConfigurationService for audit log
        email_service = instance_double('EmailConfigurationService')
        allow(EmailConfigurationService).to receive(:instance).and_return(email_service)
        allow(email_service).to receive(:settings).and_return({ provider: 'smtp' })
      end

      it 'creates audit log for successful test email' do
        expect(api_client).to receive(:post).with(
          '/api/v1/audit_logs',
          hash_including(
            action: 'test_email_sent',
            resource_type: 'TestEmail',
            source: 'worker'
          )
        )
        
        job = TestEmailJob.new
        job.execute(email_address, account_id)
      end

      it 'uses system worker authentication when account_id provided' do
        expect(SystemWorkerAuth.instance).to receive(:create_api_client).with(account_id)
        
        job = TestEmailJob.new
        job.execute(email_address, account_id)
      end

      it 'uses default authentication when no account_id provided' do
        expect_any_instance_of(TestEmailJob).to receive(:api_client)
        
        job = TestEmailJob.new
        job.execute(email_address)
      end
    end

    context 'error handling' do
      before do
        allow(PowernodeWorker.application).to receive(:env).and_return('development')
        
        # Mock services to raise error
        allow(EmailConfigurationService).to receive(:instance).and_raise(StandardError.new('Service error'))
      end

      it 'handles errors gracefully and creates failure audit log' do
        api_client = instance_double('ApiClient')
        
        # Mock SystemWorkerAuth since account_id is provided
        system_auth = instance_double('SystemWorkerAuth')
        allow(SystemWorkerAuth).to receive(:instance).and_return(system_auth)
        allow(system_auth).to receive(:create_api_client).with(account_id).and_return(api_client)
        allow(api_client).to receive(:post)
        
        job = TestEmailJob.new
        
        expect(api_client).to receive(:post).with(
          '/api/v1/audit_logs',
          hash_including(
            action: 'test_email_failed',
            resource_type: 'TestEmail'
          )
        )
        
        expect {
          job.execute(email_address, account_id)
        }.to raise_error(StandardError, 'Service error')
      end
    end
  end
end