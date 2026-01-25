# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Public::Status', type: :request do
  let(:status_service) { instance_double(System::StatusService) }

  before do
    allow(System::StatusService).to receive(:new).and_return(status_service)
  end

  describe 'GET /api/v1/public/status' do
    let(:system_status) do
      {
        overall_status: 'operational',
        components: {
          api: { status: 'operational', response_time_ms: 45 },
          database: { status: 'operational', response_time_ms: 12 },
          cache: { status: 'operational', response_time_ms: 2 }
        },
        incidents: [],
        uptime: {
          last_24_hours: 99.99,
          last_7_days: 99.95,
          last_30_days: 99.92
        },
        last_updated: Time.current.iso8601
      }
    end

    context 'without authentication' do
      it 'returns system status successfully' do
        allow(status_service).to receive(:system_status).and_return(system_status)

        get '/api/v1/public/status', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'overall_status' => 'operational',
          'components' => hash_including('api', 'database', 'cache'),
          'uptime' => hash_including('last_24_hours', 'last_7_days', 'last_30_days')
        )
      end

      it 'includes success message' do
        allow(status_service).to receive(:system_status).and_return(system_status)

        get '/api/v1/public/status', as: :json

        expect_success_response
        expect(json_response['message']).to eq('System status retrieved successfully')
      end
    end

    context 'with degraded status' do
      let(:degraded_status) do
        system_status.merge(
          overall_status: 'degraded',
          components: system_status[:components].merge(
            api: { status: 'degraded', response_time_ms: 450 }
          )
        )
      end

      it 'returns degraded status information' do
        allow(status_service).to receive(:system_status).and_return(degraded_status)

        get '/api/v1/public/status', as: :json

        expect_success_response
        data = json_response_data
        expect(data['overall_status']).to eq('degraded')
        expect(data['components']['api']['status']).to eq('degraded')
      end
    end

    context 'with active incidents' do
      let(:status_with_incidents) do
        system_status.merge(
          incidents: [
            {
              id: '1',
              title: 'API slowdown',
              status: 'investigating',
              severity: 'minor',
              started_at: 1.hour.ago.iso8601
            }
          ]
        )
      end

      it 'includes incident information' do
        allow(status_service).to receive(:system_status).and_return(status_with_incidents)

        get '/api/v1/public/status', as: :json

        expect_success_response
        data = json_response_data
        expect(data['incidents'].length).to eq(1)
        expect(data['incidents'].first).to include(
          'title' => 'API slowdown',
          'status' => 'investigating'
        )
      end
    end
  end

  describe 'GET /api/v1/public/status/summary' do
    let(:system_status) do
      {
        overall_status: 'operational',
        components: {
          api: { status: 'operational' },
          database: { status: 'operational' },
          cache: { status: 'operational' },
          worker: { status: 'degraded' }
        },
        incidents: [
          { id: '1', title: 'Minor issue' }
        ],
        uptime: {
          last_30_days: 99.95
        },
        last_updated: Time.current.iso8601
      }
    end

    context 'without authentication' do
      it 'returns simplified status summary' do
        allow(status_service).to receive(:system_status).and_return(system_status)

        get '/api/v1/public/status/summary', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'status' => 'operational',
          'components_operational' => 3,
          'components_total' => 4,
          'active_incidents' => 1,
          'uptime_30_days' => 99.95
        )
      end

      it 'includes last_updated timestamp' do
        allow(status_service).to receive(:system_status).and_return(system_status)

        get '/api/v1/public/status/summary', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('last_updated')
      end
    end

    context 'with all components down' do
      let(:all_down_status) do
        system_status.merge(
          overall_status: 'outage',
          components: {
            api: { status: 'outage' },
            database: { status: 'outage' }
          }
        )
      end

      it 'shows zero operational components' do
        allow(status_service).to receive(:system_status).and_return(all_down_status)

        get '/api/v1/public/status/summary', as: :json

        expect_success_response
        data = json_response_data
        expect(data['components_operational']).to eq(0)
        expect(data['status']).to eq('outage')
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
      allow(status_service).to receive(:system_status).and_return({})

      get '/api/v1/public/status', as: :json

      expect(response).not_to have_http_status(:unauthorized)
    end

    it 'allows unauthenticated access to summary' do
      allow(status_service).to receive(:system_status).and_return({
        overall_status: 'operational',
        components: {},
        incidents: [],
        uptime: { last_30_days: 99.9 },
        last_updated: Time.current.iso8601
      })

      get '/api/v1/public/status/summary', as: :json

      expect(response).not_to have_http_status(:unauthorized)
    end

    it 'allows unauthenticated access to history' do
      get '/api/v1/public/status/history', as: :json

      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
