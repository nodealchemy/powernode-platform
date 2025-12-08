# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::SmsDeliveryJob do
  let(:notification_id) { SecureRandom.uuid }
  let(:user_id) { SecureRandom.uuid }
  let(:mock_api_client) { instance_double(BackendApiClient) }
  let(:mock_twilio_service) { instance_double(TwilioService) }

  let(:notification) do
    {
      'id' => notification_id,
      'user_id' => user_id,
      'type' => 'payment_successful',
      'template_type' => 'payment_successful',
      'data' => { 'amount' => 9900 },
      'phone_number' => '+14155551234'
    }
  end

  let(:user_preferences) do
    { 'sms_enabled' => true }
  end

  let(:user) do
    { 'id' => user_id, 'phone_number' => '+14155551234' }
  end

  before do
    mock_powernode_worker_config
    allow_any_instance_of(described_class).to receive(:api_client).and_return(mock_api_client)
    allow(TwilioService).to receive(:new).and_return(mock_twilio_service)

    # Default API responses
    allow(mock_api_client).to receive(:get).with("/api/v1/notifications/#{notification_id}").and_return(notification)
    allow(mock_api_client).to receive(:get).with("/api/v1/users/#{user_id}/notification_preferences").and_return(user_preferences)
    allow(mock_api_client).to receive(:get).with("/api/v1/users/#{user_id}").and_return(user)
    allow(mock_api_client).to receive(:patch)
  end

  describe '#execute' do
    context 'with successful delivery' do
      before do
        allow(mock_twilio_service).to receive(:send_sms).and_return({
          success: true,
          message_sid: 'SM123456',
          segments: 1
        })
      end

      it 'sends SMS via Twilio' do
        expect(mock_twilio_service).to receive(:send_sms).with(
          to: '+14155551234',
          body: 'Payment of $99.00 received. Thank you!'
        )

        described_class.new.execute(notification_id)
      end

      it 'marks notification as delivered' do
        expect(mock_api_client).to receive(:patch).with(
          "/api/v1/notifications/#{notification_id}",
          hash_including(status: 'delivered', delivery_metadata: hash_including(channel: 'sms'))
        )

        described_class.new.execute(notification_id)
      end
    end

    context 'with SMS disabled for user' do
      let(:user_preferences) { { 'sms_enabled' => false } }

      it 'marks notification as skipped' do
        expect(mock_api_client).to receive(:patch).with(
          "/api/v1/notifications/#{notification_id}",
          hash_including(status: 'skipped', skip_reason: 'sms_disabled')
        )

        described_class.new.execute(notification_id)
      end

      it 'does not send SMS' do
        expect(mock_twilio_service).not_to receive(:send_sms)
        described_class.new.execute(notification_id)
      end
    end

    context 'with no phone number' do
      let(:notification) { super().merge('phone_number' => nil) }
      let(:user) { { 'id' => user_id, 'phone_number' => nil } }

      it 'marks notification as failed' do
        expect(mock_api_client).to receive(:patch).with(
          "/api/v1/notifications/#{notification_id}",
          hash_including(status: 'failed', error_message: 'no_phone_number')
        )

        described_class.new.execute(notification_id)
      end
    end

    context 'with delivery failure' do
      before do
        allow(mock_twilio_service).to receive(:send_sms).and_return({
          success: false,
          error: 'Phone unreachable'
        })
      end

      it 'marks notification as failed' do
        expect(mock_api_client).to receive(:patch).with(
          "/api/v1/notifications/#{notification_id}",
          hash_including(status: 'failed', error_message: 'Phone unreachable')
        )

        described_class.new.execute(notification_id)
      end
    end

    context 'with invalid phone number' do
      before do
        allow(mock_twilio_service).to receive(:send_sms)
          .and_raise(TwilioService::InvalidPhoneError.new('Invalid phone'))
      end

      it 'marks notification as failed without retrying' do
        expect(mock_api_client).to receive(:patch).with(
          "/api/v1/notifications/#{notification_id}",
          hash_including(status: 'failed')
        )

        # Should not raise - invalid phone errors don't retry
        described_class.new.execute(notification_id)
      end
    end

    context 'with configuration error' do
      before do
        allow(mock_twilio_service).to receive(:send_sms)
          .and_raise(TwilioService::ConfigurationError.new('Missing credentials'))
      end

      it 'raises error for retry' do
        expect { described_class.new.execute(notification_id) }
          .to raise_error(TwilioService::ConfigurationError)
      end
    end
  end

  describe 'message building' do
    before do
      allow(mock_twilio_service).to receive(:send_sms).and_return({
        success: true, message_sid: 'SM123', segments: 1
      })
    end

    it 'builds correct message for trial_ending' do
      notification['template_type'] = 'trial_ending'
      notification['data'] = { 'days_remaining' => 5 }

      expect(mock_twilio_service).to receive(:send_sms).with(
        hash_including(body: /trial ends in 5 days/)
      )

      described_class.new.execute(notification_id)
    end

    it 'builds correct message for payment_failed' do
      notification['template_type'] = 'payment_failed'

      expect(mock_twilio_service).to receive(:send_sms).with(
        hash_including(body: /Payment failed/)
      )

      described_class.new.execute(notification_id)
    end

    it 'builds correct message for password_reset' do
      notification['template_type'] = 'password_reset'
      notification['data'] = { 'code' => '123456' }

      expect(mock_twilio_service).to receive(:send_sms).with(
        hash_including(body: /reset code is: 123456/)
      )

      described_class.new.execute(notification_id)
    end

    it 'builds correct message for two_factor_code' do
      notification['template_type'] = 'two_factor_code'
      notification['data'] = { 'code' => '789012' }

      expect(mock_twilio_service).to receive(:send_sms).with(
        hash_including(body: /verification code is: 789012/)
      )

      described_class.new.execute(notification_id)
    end
  end
end
