# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TwilioService do
  let(:valid_env) do
    {
      'TWILIO_ACCOUNT_SID' => 'AC1234567890',
      'TWILIO_AUTH_TOKEN' => 'test_auth_token',
      'TWILIO_PHONE_NUMBER' => '+15551234567'
    }
  end

  before do
    mock_powernode_worker_config
    valid_env.each { |key, value| allow(ENV).to receive(:[]).with(key).and_return(value) }
    allow(ENV).to receive(:fetch).and_call_original
  end

  describe '#initialize' do
    context 'with valid configuration' do
      it 'creates service instance without errors' do
        expect { described_class.new }.not_to raise_error
      end
    end

    context 'with missing configuration' do
      it 'raises ConfigurationError when TWILIO_ACCOUNT_SID is missing' do
        allow(ENV).to receive(:[]).with('TWILIO_ACCOUNT_SID').and_return(nil)
        expect { described_class.new }.to raise_error(TwilioService::ConfigurationError, /TWILIO_ACCOUNT_SID/)
      end

      it 'raises ConfigurationError when TWILIO_AUTH_TOKEN is missing' do
        allow(ENV).to receive(:[]).with('TWILIO_AUTH_TOKEN').and_return(nil)
        expect { described_class.new }.to raise_error(TwilioService::ConfigurationError, /TWILIO_AUTH_TOKEN/)
      end

      it 'raises ConfigurationError when TWILIO_PHONE_NUMBER is missing' do
        allow(ENV).to receive(:[]).with('TWILIO_PHONE_NUMBER').and_return(nil)
        allow(ENV).to receive(:[]).with('TWILIO_FROM_NUMBER').and_return(nil)
        expect { described_class.new }.to raise_error(TwilioService::ConfigurationError, /TWILIO_PHONE_NUMBER/)
      end
    end
  end

  describe '#send_sms' do
    let(:service) { described_class.new }
    let(:mock_client) { instance_double(Twilio::REST::Client) }
    let(:mock_messages) { double('messages') }
    let(:mock_message) do
      double('message', sid: 'SM123456', status: 'queued')
    end

    before do
      allow(Twilio::REST::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:messages).and_return(mock_messages)
    end

    context 'with valid phone number' do
      let(:to) { '+14155551234' }
      let(:body) { 'Test message' }

      before do
        allow(mock_messages).to receive(:create).and_return(mock_message)
      end

      it 'sends SMS successfully' do
        result = service.send_sms(to: to, body: body)

        expect(result[:success]).to be true
        expect(result[:message_sid]).to eq('SM123456')
      end

      it 'calculates message segments correctly for short messages' do
        result = service.send_sms(to: to, body: 'Short')
        expect(result[:segments]).to eq(1)
      end

      it 'calculates message segments correctly for long messages' do
        long_body = 'x' * 320
        result = service.send_sms(to: to, body: long_body)
        expect(result[:segments]).to eq(3)
      end

      it 'truncates messages over 1600 characters' do
        very_long_body = 'x' * 2000
        expect(mock_messages).to receive(:create).with(
          hash_including(body: 'x' * 1600)
        )
        service.send_sms(to: to, body: very_long_body)
      end
    end

    context 'with invalid phone number' do
      it 'raises InvalidPhoneError for malformed phone numbers' do
        expect { service.send_sms(to: 'invalid', body: 'Test') }
          .to raise_error(TwilioService::InvalidPhoneError)
      end

      it 'raises InvalidPhoneError when Twilio returns 21211' do
        # Create a mock response object that RestError expects
        mock_response = double('Response',
          status_code: 400,
          body: { 'code' => 21211, 'message' => 'Invalid To number' }
        )
        twilio_error = Twilio::REST::RestError.new('Invalid To number', mock_response)

        allow(mock_messages).to receive(:create).and_raise(twilio_error)

        expect { service.send_sms(to: '+14155551234', body: 'Test') }
          .to raise_error(TwilioService::InvalidPhoneError)
      end
    end

    context 'phone number normalization' do
      it 'adds + prefix if missing' do
        expect(mock_messages).to receive(:create).with(
          hash_including(to: '+14155551234')
        ).and_return(mock_message)

        service.send_sms(to: '14155551234', body: 'Test')
      end

      it 'removes spaces and dashes' do
        expect(mock_messages).to receive(:create).with(
          hash_including(to: '+14155551234')
        ).and_return(mock_message)

        service.send_sms(to: '+1 (415) 555-1234', body: 'Test')
      end
    end
  end

  describe '#send_bulk_sms' do
    let(:service) { described_class.new }
    let(:mock_client) { instance_double(Twilio::REST::Client) }
    let(:mock_messages) { double('messages') }

    before do
      allow(Twilio::REST::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:messages).and_return(mock_messages)
    end

    it 'sends multiple messages and returns aggregated results' do
      allow(mock_messages).to receive(:create)
        .and_return(double('message', sid: 'SM123', status: 'queued'))

      messages = [
        { to: '+14155551234', body: 'Message 1' },
        { to: '+14155551235', body: 'Message 2' }
      ]

      result = service.send_bulk_sms(messages)

      expect(result[:total]).to eq(2)
      expect(result[:sent]).to eq(2)
      expect(result[:failed]).to eq(0)
      expect(result[:success]).to be true
    end

    it 'handles partial failures' do
      call_count = 0
      allow(mock_messages).to receive(:create) do
        call_count += 1
        if call_count == 1
          double('message', sid: 'SM123', status: 'queued')
        else
          raise StandardError, 'Failed'
        end
      end

      messages = [
        { to: '+14155551234', body: 'Message 1' },
        { to: '+14155551235', body: 'Message 2' }
      ]

      result = service.send_bulk_sms(messages)

      expect(result[:sent]).to eq(1)
      expect(result[:failed]).to eq(1)
      expect(result[:success]).to be false
    end
  end

  describe '#get_message_status' do
    let(:service) { described_class.new }
    let(:mock_client) { instance_double(Twilio::REST::Client) }

    before do
      allow(Twilio::REST::Client).to receive(:new).and_return(mock_client)
    end

    it 'fetches message status' do
      mock_message = double('message',
        sid: 'SM123',
        status: 'delivered',
        error_code: nil,
        error_message: nil,
        date_sent: Time.now,
        date_updated: Time.now
      )
      allow(mock_client).to receive(:messages).and_return(double(fetch: mock_message))

      result = service.get_message_status('SM123')

      expect(result[:success]).to be true
      expect(result[:status]).to eq('delivered')
    end
  end
end
