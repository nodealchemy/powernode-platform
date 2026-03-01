# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Chat::Channels - Metrics & Cleanup', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }
  let(:channel) { create(:chat_channel, account: account) }

  describe 'GET /api/v1/chat/channels/:id/metrics' do
    context 'with no data' do
      it 'returns all expected fields with zero/null values' do
        get "/api/v1/chat/channels/#{channel.id}/metrics", headers: headers, as: :json

        expect_success_response
        metrics = json_response_data['metrics']

        %w[total_sessions active_sessions total_messages messages_today
           avg_response_time_ms resolution_rate messages_per_hour
           avg_session_duration_ms error_rate last_message_at status].each do |field|
          expect(metrics).to have_key(field), "Missing field: #{field}"
        end

        expect(metrics['total_sessions']).to eq(0)
        expect(metrics['active_sessions']).to eq(0)
        expect(metrics['total_messages']).to eq(0)
        expect(metrics['status']).to eq(channel.status)
      end
    end

    context 'with messages' do
      let!(:session) { create(:chat_session, channel: channel) }

      before do
        create(:chat_message, :inbound, session: session, created_at: 10.minutes.ago)
        create(:chat_message, :outbound, session: session, created_at: 5.minutes.ago)
        create(:chat_message, :inbound, session: session, created_at: 2.minutes.ago)
      end

      it 'calculates metrics with messages present' do
        get "/api/v1/chat/channels/#{channel.id}/metrics", headers: headers, as: :json

        expect_success_response
        metrics = json_response_data['metrics']
        expect(metrics['total_messages']).to eq(3)
        expect(metrics['avg_response_time_ms']).to be_a(Numeric) if metrics['avg_response_time_ms']
      end
    end

    context 'with closed sessions' do
      before do
        create(:chat_session, :closed, channel: channel, closed_at: 1.hour.ago)
        create(:chat_session, :active, channel: channel)
      end

      it 'calculates resolution_rate' do
        get "/api/v1/chat/channels/#{channel.id}/metrics", headers: headers, as: :json

        expect_success_response
        metrics = json_response_data['metrics']
        expect(metrics['resolution_rate']).to eq(50.0)
      end
    end

    context 'with failed messages' do
      let!(:session) { create(:chat_session, channel: channel) }

      before do
        create(:chat_message, :outbound, :failed, session: session)
        create(:chat_message, :outbound, :delivered, session: session)
      end

      it 'calculates error_rate' do
        get "/api/v1/chat/channels/#{channel.id}/metrics", headers: headers, as: :json

        expect_success_response
        metrics = json_response_data['metrics']
        expect(metrics['error_rate']).to eq(50.0)
      end
    end
  end

  describe 'POST /api/v1/chat/channels/cleanup_sessions' do
    it 'returns cleanup counts' do
      post '/api/v1/chat/channels/cleanup_sessions', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('channels_processed')
      expect(data).to have_key('total_idled')
      expect(data).to have_key('total_closed')
    end

    context 'with stale sessions' do
      let!(:channel) { create(:chat_channel, account: account) }
      let!(:stale_active) { create(:chat_session, :active, channel: channel, last_activity_at: 2.days.ago) }
      let!(:stale_idle) { create(:chat_session, :idle, channel: channel, last_activity_at: 10.days.ago) }
      let!(:fresh_active) { create(:chat_session, :active, channel: channel, last_activity_at: 1.hour.ago) }

      it 'idles stale active and closes stale idle sessions' do
        post '/api/v1/chat/channels/cleanup_sessions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['total_idled']).to be >= 1
        expect(data['total_closed']).to be >= 1

        expect(stale_active.reload.status).to eq('idle')
        expect(stale_idle.reload.status).to eq('closed')
        expect(fresh_active.reload.status).to eq('active')
      end
    end
  end
end
