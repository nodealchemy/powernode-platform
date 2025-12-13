# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FirebaseService do
  let(:valid_env) do
    {
      'FIREBASE_PROJECT_ID' => 'test-project',
      'GOOGLE_APPLICATION_CREDENTIALS' => '/path/to/credentials.json',
      'FIREBASE_CREDENTIALS_JSON' => nil
    }
  end

  let(:mock_fcm_service) { instance_double(Google::Apis::FcmV1::FirebaseCloudMessagingService) }

  before do
    mock_powernode_worker_config
    valid_env.each { |key, value| allow(ENV).to receive(:[]).with(key).and_return(value) }
    allow(ENV).to receive(:fetch).and_call_original
    allow(File).to receive(:exist?).with('/path/to/credentials.json').and_return(true)
    allow(File).to receive(:open).with('/path/to/credentials.json').and_return(StringIO.new('{}'))
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(double)
    allow(Google::Apis::FcmV1::FirebaseCloudMessagingService).to receive(:new).and_return(mock_fcm_service)
    allow(mock_fcm_service).to receive(:authorization=)
  end

  describe '#initialize' do
    context 'with valid configuration' do
      it 'creates service instance without errors' do
        expect { described_class.new }.not_to raise_error
      end
    end

    context 'with missing configuration' do
      it 'raises ConfigurationError when FIREBASE_PROJECT_ID is missing' do
        allow(ENV).to receive(:[]).with('FIREBASE_PROJECT_ID').and_return(nil)
        expect { described_class.new }.to raise_error(FirebaseService::ConfigurationError, /FIREBASE_PROJECT_ID/)
      end

      it 'raises ConfigurationError when credentials are missing' do
        allow(ENV).to receive(:[]).with('GOOGLE_APPLICATION_CREDENTIALS').and_return(nil)
        allow(ENV).to receive(:[]).with('FIREBASE_CREDENTIALS_JSON').and_return(nil)
        expect { described_class.new }.to raise_error(FirebaseService::ConfigurationError, /credentials/)
      end
    end
  end

  describe '#send_notification' do
    let(:service) { described_class.new }
    let(:device_token) { 'test_device_token_1234567890' }
    let(:title) { 'Test Title' }
    let(:body) { 'Test notification body' }

    context 'with successful delivery' do
      before do
        allow(mock_fcm_service).to receive(:send_message)
          .and_return(double(name: 'projects/test-project/messages/12345'))
      end

      it 'sends notification successfully' do
        result = service.send_notification(
          device_token: device_token,
          title: title,
          body: body
        )

        expect(result[:success]).to be true
        expect(result[:message_id]).to include('12345')
        expect(result[:device_token]).to eq(device_token)
      end

      it 'includes custom data payload' do
        expect(mock_fcm_service).to receive(:send_message) do |project, request|
          # Implementation uses transform_values(&:to_s) which keeps symbol keys
          expect(request.message.data).to eq({ key: 'value' })
          double(name: 'projects/test-project/messages/12345')
        end

        service.send_notification(
          device_token: device_token,
          title: title,
          body: body,
          data: { key: 'value' }
        )
      end
    end

    context 'with invalid token' do
      before do
        error_body = { 'error' => { 'details' => [{ 'errorCode' => 'UNREGISTERED' }] } }.to_json
        allow(mock_fcm_service).to receive(:send_message)
          .and_raise(Google::Apis::ClientError.new('Invalid', body: error_body))
      end

      it 'returns invalid_token flag' do
        result = service.send_notification(
          device_token: device_token,
          title: title,
          body: body
        )

        expect(result[:success]).to be false
        expect(result[:invalid_token]).to be true
      end
    end

    context 'with quota exceeded' do
      before do
        error_body = { 'error' => { 'details' => [{ 'errorCode' => 'QUOTA_EXCEEDED' }] } }.to_json
        allow(mock_fcm_service).to receive(:send_message)
          .and_raise(Google::Apis::ClientError.new('Quota', body: error_body))
      end

      it 'raises DeliveryError' do
        expect {
          service.send_notification(
            device_token: device_token,
            title: title,
            body: body
          )
        }.to raise_error(FirebaseService::DeliveryError, /quota/)
      end
    end
  end

  describe '#send_multicast' do
    let(:service) { described_class.new }
    let(:device_tokens) { ['token1', 'token2', 'token3'] }

    it 'sends to multiple devices' do
      allow(mock_fcm_service).to receive(:send_message)
        .and_return(double(name: 'projects/test-project/messages/12345'))

      result = service.send_multicast(
        device_tokens: device_tokens,
        title: 'Test',
        body: 'Message'
      )

      expect(result[:total]).to eq(3)
      expect(result[:sent]).to eq(3)
      expect(result[:success]).to be true
    end

    it 'collects invalid tokens' do
      call_count = 0
      allow(mock_fcm_service).to receive(:send_message) do
        call_count += 1
        if call_count == 2
          error_body = { 'error' => { 'details' => [{ 'errorCode' => 'INVALID_ARGUMENT' }] } }.to_json
          raise Google::Apis::ClientError.new('Invalid', body: error_body)
        end
        double(name: 'projects/test-project/messages/12345')
      end

      result = service.send_multicast(
        device_tokens: device_tokens,
        title: 'Test',
        body: 'Message'
      )

      expect(result[:invalid_tokens]).to include('token2')
      expect(result[:sent]).to eq(2)
    end
  end

  describe '#send_to_topic' do
    let(:service) { described_class.new }

    it 'sends notification to topic' do
      allow(mock_fcm_service).to receive(:send_message)
        .and_return(double(name: 'projects/test-project/messages/12345'))

      result = service.send_to_topic(
        topic: 'news',
        title: 'Breaking News',
        body: 'Important update'
      )

      expect(result[:success]).to be true
      expect(result[:topic]).to eq('news')
    end
  end
end
