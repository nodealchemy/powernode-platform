# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Version', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/version' do
    context 'without authentication' do
      it 'returns semantic version information' do
        allow(Powernode::Version).to receive(:semantic_version).and_return({
          version: '1.0.0',
          major: 1,
          minor: 0,
          patch: 0
        })

        get '/api/v1/version', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('version')
      end
    end

    context 'with authentication' do
      it 'returns version information' do
        allow(Powernode::Version).to receive(:semantic_version).and_return({
          version: '1.0.0'
        })

        get '/api/v1/version', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/version/full' do
    context 'with authentication' do
      it 'returns full version information' do
        allow(Powernode::Version).to receive(:full_version_info).and_return({
          version: '1.0.0',
          build: '12345',
          git_sha: 'abc123',
          environment: 'test'
        })

        get '/api/v1/version/full', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('version')
        expect(data).to have_key('environment')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/version/full', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/version/health' do
    context 'without authentication' do
      it 'returns health status' do
        allow(Powernode::Version).to receive(:current).and_return('1.0.0')

        get '/api/v1/version/health', as: :json

        expect_success_response
        data = json_response_data
        expect(data['status']).to eq('healthy')
        expect(data['version']).to eq('1.0.0')
        expect(data).to have_key('timestamp')
        expect(data).to have_key('uptime')
      end

      it 'returns uptime information' do
        boot_time = 1.hour.ago
        allow(Rails.application.config).to receive(:boot_time).and_return(boot_time)

        get '/api/v1/version/health', as: :json

        expect_success_response
        data = json_response_data
        uptime = data['uptime']
        expect(uptime).to have_key('boot_time')
        expect(uptime).to have_key('uptime_seconds')
        expect(uptime).to have_key('uptime_human')
        expect(uptime['uptime_seconds']).to be > 0
      end

      it 'formats uptime in human readable format' do
        boot_time = 2.days.ago
        allow(Rails.application.config).to receive(:boot_time).and_return(boot_time)

        get '/api/v1/version/health', as: :json

        expect_success_response
        data = json_response_data
        expect(data['uptime']['uptime_human']).to match(/\d+d/)
      end
    end

    context 'with authentication' do
      it 'returns health status' do
        allow(Powernode::Version).to receive(:current).and_return('1.0.0')

        get '/api/v1/version/health', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['status']).to eq('healthy')
      end
    end
  end
end
