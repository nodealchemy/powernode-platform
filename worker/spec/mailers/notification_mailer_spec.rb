# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NotificationMailer, type: :mailer do
  # Keep the mailer hermetic: avoid the EmailConfigurationService network fetch.
  before do
    config = instance_double(
      EmailConfigurationService,
      settings: { smtp_from_address: 'noreply@powernode.dev', smtp_from_name: 'Powernode' }
    )
    allow(EmailConfigurationService).to receive(:instance).and_return(config)
  end

  describe '#alert_email' do
    let(:mail) do
      described_class.alert_email(
        recipient: 'security@example.com',
        subject: 'Security Alert: suspicious_activity',
        heading: 'Security Alert',
        body: 'A security event was detected: suspicious_activity.',
        details: { 'ip_address' => '10.0.0.1', 'location' => 'Unknown' }
      )
    end

    it 'addresses the recipient with the given subject' do
      expect(mail.to).to eq(['security@example.com'])
      expect(mail.subject).to eq('Security Alert: suspicious_activity')
    end

    it 'renders the heading, body and details into the email body' do
      body = mail.body.encoded
      expect(body).to include('Security Alert')
      expect(body).to include('A security event was detected: suspicious_activity.')
      expect(body).to include('10.0.0.1')
    end
  end

  # Regression guard for IMP-cd78fa6e7522: the mailer's `api_client` used to
  # reference a constant that config/boot.rb never required (the worker has no
  # autoloader), so every fetch_* raised NameError, was swallowed by the bare
  # `rescue StandardError`, and every one of these mails silently never sent.
  # These examples must exercise REAL constant resolution and a REAL HTTP round
  # trip — stubbing `api_client` would pass against the broken code.
  describe 'backend API client wiring' do
    before { mock_powernode_worker_config }

    it 'uses BackendApiClient, which config/boot.rb actually requires' do
      expect(described_class.new.send(:api_client)).to be_a(BackendApiClient)
    end
  end

  describe '#welcome_email' do
    let(:user_id) { '019f7cb5-3858-7000-8000-000000000001' }

    before do
      mock_powernode_worker_config
      stub_request(:get, "http://localhost:3000/api/v1/internal/users/#{user_id}")
        .to_return(
          status: 200,
          body: {
            success: true,
            data: { id: user_id, email: 'newuser@example.com', name: 'New User' }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'delivers to the address returned by the internal users endpoint' do
      mail = described_class.welcome_email(user_id)

      expect(mail.to).to eq(['newuser@example.com'])
      expect(mail.subject).to eq('Welcome to Powernode!')
    end
  end

  describe '#invitation_email' do
    let(:invitation_id) { '019f7cb5-3858-7000-8000-000000000002' }

    before do
      mock_powernode_worker_config
      stub_request(:get, "http://localhost:3000/api/v1/internal/invitations/#{invitation_id}")
        .to_return(
          status: 200,
          body: {
            success: true,
            data: {
              id: invitation_id,
              email: 'invitee@example.com',
              first_name: 'Ada',
              last_name: 'Lovelace',
              account_name: 'Acme',
              role_names: ['Member'],
              expires_at: '2026-09-01T00:00:00Z',
              inviter_first_name: 'Grace',
              inviter_last_name: 'Hopper'
            }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'delivers to the invitee returned by the internal invitations endpoint' do
      mail = described_class.invitation_email(invitation_id, 'tok-123')

      expect(mail.to).to eq(['invitee@example.com'])
      expect(mail.subject).to include('Acme')
    end

    # invitation_email's templates call app_name, a private mailer method.
    # Without `helper_method :app_name` the render raises NameError, so this
    # asserts the rendered body, not just the envelope.
    it 'renders app_name into the body via the exposed helper' do
      body = described_class.invitation_email(invitation_id, 'tok-123').body.encoded

      expect(body).to include('Powernode')
      expect(body).to include('Grace Hopper')
    end
  end

  # email_verification / subscription_renewal / payment_failed /
  # subscription_cancelled have no ERB templates yet (a separate defect,
  # documented on the mailer), so assert the account lookup itself
  # rather than a delivery: real constant resolution, real HTTP, real envelope
  # unwrap of the nested data.account payload.
  describe 'account lookup' do
    let(:account_id) { '019f7cb5-3858-7000-8000-000000000003' }

    before do
      mock_powernode_worker_config
      stub_request(:get, "http://localhost:3000/api/v1/internal/accounts/#{account_id}")
        .to_return(
          status: 200,
          body: {
            success: true,
            data: { account: { id: account_id, name: 'Acme', billing_email: 'billing@example.com' } }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns the symbol-keyed account the mailer actions index into' do
      account = described_class.new.send(:fetch_account, account_id)

      expect(account).to include(billing_email: 'billing@example.com', name: 'Acme')
    end
  end

  # The three fetch_* helpers used to bind the exception and throw it away, so a
  # missing constant, a timeout and a 404 were indistinguishable in the logs
  # (there were none). The lookup must still degrade to nil, but say why.
  describe 'lookup failure diagnostics' do
    let(:worker_logger) { instance_double(Logger, error: nil, warn: nil, info: nil, debug: nil) }

    before do
      mock_powernode_worker_config
      allow(PowernodeWorker.application).to receive(:logger).and_return(worker_logger)
      allow_any_instance_of(BackendApiClient).to receive(:get_internal_user)
        .and_raise(BackendApiClient::ApiError.new('Resource not found', 404))
    end

    it 'logs the exception class and message before degrading to nil' do
      described_class.welcome_email('missing-user-id').message

      expect(worker_logger).to have_received(:error)
        .with(/BackendApiClient::ApiError.*Resource not found/).at_least(:once)
    end

    it 'still returns a non-delivering mail rather than raising' do
      expect { described_class.welcome_email('missing-user-id').message }.not_to raise_error
    end
  end
end
