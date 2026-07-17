# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Extensions', type: :request do
  describe 'GET /api/v1/extensions/ui' do
    context 'without authentication' do
      it 'returns 200 with an extensions array' do
        get '/api/v1/extensions/ui', as: :json

        expect_success_response
        expect(json_response['data']).to have_key('extensions')
        expect(json_response['data']['extensions']).to be_an(Array)
      end

      it 'echoes the frontend_extensions enumeration verbatim' do
        allow(Shared::FeatureGateService).to receive(:frontend_extensions).and_return(
          [
            { slug: 'system', version: '0.1.0', enabled: true },
            { slug: 'marketing', version: '0.2.0', enabled: false }
          ]
        )

        get '/api/v1/extensions/ui', as: :json

        expect_success_response
        extensions = json_response['data']['extensions']
        expect(extensions).to contain_exactly(
          { 'slug' => 'system', 'version' => '0.1.0', 'enabled' => true },
          { 'slug' => 'marketing', 'version' => '0.2.0', 'enabled' => false }
        )
      end

      it 'reports each extension with slug, version, and enabled' do
        allow(Shared::FeatureGateService).to receive(:frontend_extensions).and_return(
          [ { slug: 'system', version: '0.1.0', enabled: true } ]
        )

        get '/api/v1/extensions/ui', as: :json

        expect_success_response
        expect(json_response['data']['extensions'].first).to include(
          'slug', 'version', 'enabled'
        )
      end

      it 'returns an empty array in core mode (no extensions on disk)' do
        allow(Shared::FeatureGateService).to receive(:frontend_extensions).and_return([])

        get '/api/v1/extensions/ui', as: :json

        expect_success_response
        expect(json_response['data']['extensions']).to eq([])
      end
    end
  end
end
