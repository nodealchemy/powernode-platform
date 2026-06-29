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
end
