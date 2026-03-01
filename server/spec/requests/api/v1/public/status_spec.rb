# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Public::Status', type: :request do
  describe 'GET /api/v1/public/status' do
    context 'without authentication' do
      it 'returns system status successfully' do
        get '/api/v1/public/status', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'overall_status',
          'components',
          'uptime'
        )
      end

      it 'includes success message' do
        get '/api/v1/public/status', as: :json

        expect_success_response
        expect(json_response['message']).to eq('System status retrieved successfully')
      end
    end
  end

  describe 'GET /api/v1/public/status/summary' do
    context 'without authentication' do
      it 'returns simplified status summary' do
        get '/api/v1/public/status/summary', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'status',
          'components_operational',
          'components_total',
          'active_incidents',
          'uptime_30_days'
        )
      end

      it 'includes last_updated timestamp' do
        get '/api/v1/public/status/summary', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('last_updated')
      end
    end
  end

  describe 'GET /api/v1/public/status/history' do
    context 'without authentication' do
      it 'returns historical status data' do
        get '/api/v1/public/status/history', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('period', 'uptime_percentage', 'daily_status', 'incidents_count', 'average_response_time_ms')
        expect(data['period']).to eq('last_30_days')
      end

      it 'includes 30 days of daily status' do
        get '/api/v1/public/status/history', as: :json

        expect_success_response
        data = json_response_data
        expect(data['daily_status']).to be_an(Array)
        expect(data['daily_status'].length).to eq(30)
      end

      it 'includes date and status for each day' do
        get '/api/v1/public/status/history', as: :json

        expect_success_response
        data = json_response_data
        first_day = data['daily_status'].first
        expect(first_day).to include(
          'date',
          'status',
          'uptime_percentage'
        )
      end

      it 'orders daily status from oldest to newest' do
        get '/api/v1/public/status/history', as: :json

        expect_success_response
        data = json_response_data
        dates = data['daily_status'].map { |d| Date.parse(d['date']) }
        expect(dates).to eq(dates.sort)
      end
    end
  end

  describe 'public access' do
    it 'allows unauthenticated access to index' do
      get '/api/v1/public/status', as: :json

      expect(response).not_to have_http_status(:unauthorized)
    end

    it 'allows unauthenticated access to summary' do
      get '/api/v1/public/status/summary', as: :json

      expect(response).not_to have_http_status(:unauthorized)
    end

    it 'allows unauthenticated access to history' do
      get '/api/v1/public/status/history', as: :json

      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
