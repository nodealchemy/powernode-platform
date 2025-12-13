# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::PushNotificationJob do
  let(:notification_id) { SecureRandom.uuid }
  let(:user_id) { SecureRandom.uuid }
  let(:mock_api_client) { instance_double(BackendApiClient) }
  let(:mock_firebase_service) { instance_double(FirebaseService) }

  let(:notification) do
    {
      'id' => notification_id,
      'user_id' => user_id,
      'type' => 'payment_successful',
      'template_type' => 'payment_successful',
      'data' => { 'amount' => 9900 },
      'title' => nil,
      'body' => nil
    }
  end

  let(:user_preferences) do
    { 'push_enabled' => true }
  end

  let(:devices) do
    [
      { 'id' => '1', 'push_token' => 'token_abc123', 'push_enabled' => true },
      { 'id' => '2', 'push_token' => 'token_def456', 'push_enabled' => true }
    ]
  end

  before do
    mock_powernode_worker_config
    allow_any_instance_of(described_class).to receive(:api_client).and_return(mock_api_client)
    allow(FirebaseService).to receive(:new).and_return(mock_firebase_service)

    # Default API responses
    allow(mock_api_client).to receive(:get).with("/api/v1/notifications/#{notification_id}").and_return(notification)
    allow(mock_api_client).to receive(:get).with("/api/v1/users/#{user_id}/notification_preferences").and_return(user_preferences)
    allow(mock_api_client).to receive(:get).with("/api/v1/users/#{user_id}/devices").and_return(devices)
    allow(mock_api_client).to receive(:patch)
    allow(mock_api_client).to receive(:delete)
  end

  describe '#execute' do
    context 'with single device' do
      let(:devices) { [{ 'id' => '1', 'push_token' => 'token_abc123', 'push_enabled' => true }] }

      context 'with successful delivery' do
        before do
          allow(mock_firebase_service).to receive(:send_notification).and_return({
            success: true,
            message_id: 'msg_123',
            device_token: 'token_abc123'
          })
        end

        it 'sends push notification via Firebase' do
          expect(mock_firebase_service).to receive(:send_notification).with(
            device_token: 'token_abc123',
            title: 'Payment Received',
            body: 'Payment of $99.00 received successfully.',
            data: hash_including(:notification_id, :type),
            options: hash_including(:sound, :channel_id)
          )

          described_class.new.execute(notification_id)
        end

        it 'marks notification as delivered' do
          expect(mock_api_client).to receive(:patch).with(
            "/api/v1/notifications/#{notification_id}",
            hash_including(status: 'delivered', delivery_metadata: hash_including(channel: 'push'))
          )

          described_class.new.execute(notification_id)
        end
      end

      context 'with invalid token' do
        before do
          allow(mock_firebase_service).to receive(:send_notification).and_return({
            success: false,
            invalid_token: true,
            device_token: 'token_abc123'
          })
        end

        it 'removes invalid token' do
          expect(mock_api_client).to receive(:delete).with('/api/v1/devices/by_token/token_abc123')
          described_class.new.execute(notification_id)
        end

        it 'marks notification as failed' do
          expect(mock_api_client).to receive(:patch).with(
            "/api/v1/notifications/#{notification_id}",
            hash_including(status: 'failed', error_message: 'invalid_device_token')
          )

          described_class.new.execute(notification_id)
        end
      end
    end

    context 'with multiple devices (multicast)' do
      context 'with successful delivery to all' do
        before do
          allow(mock_firebase_service).to receive(:send_multicast).and_return({
            success: true,
            total: 2,
            sent: 2,
            failed: 0,
            invalid_tokens: []
          })
        end

        it 'sends multicast notification' do
          expect(mock_firebase_service).to receive(:send_multicast).with(
            device_tokens: ['token_abc123', 'token_def456'],
            title: 'Payment Received',
            body: 'Payment of $99.00 received successfully.',
            data: hash_including(:notification_id, :type)
          )

          described_class.new.execute(notification_id)
        end

        it 'marks notification as delivered with device count' do
          expect(mock_api_client).to receive(:patch).with(
            "/api/v1/notifications/#{notification_id}",
            hash_including(
              status: 'delivered',
              delivery_metadata: hash_including(devices_sent: 2, devices_failed: 0)
            )
          )

          described_class.new.execute(notification_id)
        end
      end

      context 'with partial failure' do
        before do
          allow(mock_firebase_service).to receive(:send_multicast).and_return({
            success: false,
            total: 2,
            sent: 1,
            failed: 1,
            invalid_tokens: ['token_def456']
          })
        end

        it 'marks notification as partial' do
          expect(mock_api_client).to receive(:patch).with(
            "/api/v1/notifications/#{notification_id}",
            hash_including(status: 'partial', delivery_metadata: hash_including(sent: 1, failed: 1))
          )

          described_class.new.execute(notification_id)
        end

        it 'removes invalid tokens' do
          expect(mock_api_client).to receive(:delete).with('/api/v1/devices/by_token/token_def456')
          described_class.new.execute(notification_id)
        end
      end
    end

    context 'with push disabled for user' do
      let(:user_preferences) { { 'push_enabled' => false } }

      it 'marks notification as skipped' do
        expect(mock_api_client).to receive(:patch).with(
          "/api/v1/notifications/#{notification_id}",
          hash_including(status: 'skipped', skip_reason: 'push_disabled')
        )

        described_class.new.execute(notification_id)
      end
    end

    context 'with no device tokens' do
      let(:devices) { [] }

      it 'marks notification as failed' do
        expect(mock_api_client).to receive(:patch).with(
          "/api/v1/notifications/#{notification_id}",
          hash_including(status: 'failed', error_message: 'no_device_tokens')
        )

        described_class.new.execute(notification_id)
      end
    end

    context 'with Firebase configuration error' do
      before do
        allow(mock_firebase_service).to receive(:send_notification)
          .and_raise(FirebaseService::ConfigurationError.new('Invalid project'))
      end

      let(:devices) { [{ 'id' => '1', 'push_token' => 'token_abc123', 'push_enabled' => true }] }

      it 'raises error for retry' do
        expect { described_class.new.execute(notification_id) }
          .to raise_error(FirebaseService::ConfigurationError)
      end
    end
  end

  describe 'title and body building' do
    let(:devices) { [{ 'id' => '1', 'push_token' => 'token_abc123', 'push_enabled' => true }] }

    before do
      allow(mock_firebase_service).to receive(:send_notification).and_return({
        success: true, message_id: 'msg_123', device_token: 'token_abc123'
      })
    end

    it 'builds title for trial_ending' do
      notification['template_type'] = 'trial_ending'

      expect(mock_firebase_service).to receive(:send_notification).with(
        hash_including(title: 'Trial Ending Soon')
      )

      described_class.new.execute(notification_id)
    end

    it 'builds title for payment_failed' do
      notification['template_type'] = 'payment_failed'

      expect(mock_firebase_service).to receive(:send_notification).with(
        hash_including(title: 'Payment Failed')
      )

      described_class.new.execute(notification_id)
    end

    it 'builds body for trial_ending with days' do
      notification['template_type'] = 'trial_ending'
      notification['data'] = { 'days_remaining' => 3 }

      expect(mock_firebase_service).to receive(:send_notification).with(
        hash_including(body: /trial ends in 3 days/)
      )

      described_class.new.execute(notification_id)
    end
  end

  describe 'deep linking' do
    let(:devices) { [{ 'id' => '1', 'push_token' => 'token_abc123', 'push_enabled' => true }] }

    before do
      allow(mock_firebase_service).to receive(:send_notification).and_return({
        success: true, message_id: 'msg_123', device_token: 'token_abc123'
      })
    end

    it 'includes billing deep link for payment notifications' do
      notification['template_type'] = 'payment_failed'

      expect(mock_firebase_service).to receive(:send_notification).with(
        hash_including(data: hash_including(deep_link: 'powernode://billing'))
      )

      described_class.new.execute(notification_id)
    end

    it 'includes security deep link for password reset' do
      notification['template_type'] = 'password_reset'

      expect(mock_firebase_service).to receive(:send_notification).with(
        hash_including(data: hash_including(deep_link: 'powernode://security'))
      )

      described_class.new.execute(notification_id)
    end
  end
end
