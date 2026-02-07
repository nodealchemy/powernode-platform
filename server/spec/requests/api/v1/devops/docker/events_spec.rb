# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Docker::Events', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read) { create(:user, account: account, permissions: ['docker.events.read']) }
  let(:user_with_ack) { create(:user, account: account, permissions: ['docker.events.read', 'docker.events.acknowledge']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }

  describe 'GET /api/v1/devops/docker/hosts/:host_id/events' do
    let(:headers) { auth_headers_for(user_with_read) }

    before do
      create_list(:devops_docker_event, 3, docker_host: host)
    end

    it 'returns list of events' do
      get "/api/v1/devops/docker/hosts/#{host.id}/events", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['items']).to be_an(Array)
      expect(response_data['data']['items'].length).to eq(3)
    end

    it 'includes pagination' do
      get "/api/v1/devops/docker/hosts/#{host.id}/events", headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']['pagination']).to include(
        'current_page', 'per_page', 'total_pages', 'total_count'
      )
    end

    it 'filters by severity' do
      create(:devops_docker_event, :critical, docker_host: host)

      get "/api/v1/devops/docker/hosts/#{host.id}/events?severity=critical",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      severities = response_data['data']['items'].map { |e| e['severity'] }
      expect(severities.uniq).to eq(['critical'])
    end

    it 'filters by acknowledged status' do
      create(:devops_docker_event, :acknowledged, docker_host: host)

      get "/api/v1/devops/docker/hosts/#{host.id}/events?acknowledged=false",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      acks = response_data['data']['items'].map { |e| e['acknowledged'] }
      expect(acks).to all(be false)
    end

    it 'filters by source_type' do
      create(:devops_docker_event, docker_host: host, source_type: 'container')

      get "/api/v1/devops/docker/hosts/#{host.id}/events?source_type=container",
          headers: headers, as: :json

      expect_success_response
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get "/api/v1/devops/docker/hosts/#{host.id}/events", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/events/:id' do
    let(:headers) { auth_headers_for(user_with_read) }
    let(:event) { create(:devops_docker_event, docker_host: host) }

    it 'returns event details' do
      get "/api/v1/devops/docker/hosts/#{host.id}/events/#{event.id}", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['event']['id']).to eq(event.id)
      expect(response_data['data']['event']['severity']).to eq(event.severity)
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:host_id/events/:id/acknowledge' do
    let(:headers) { auth_headers_for(user_with_ack) }
    let(:event) { create(:devops_docker_event, docker_host: host) }

    it 'acknowledges the event' do
      post "/api/v1/devops/docker/hosts/#{host.id}/events/#{event.id}/acknowledge",
           headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['event']['acknowledged']).to be true

      event.reload
      expect(event.acknowledged).to be true
      expect(event.acknowledged_by).to eq(user_with_ack)
      expect(event.acknowledged_at).to be_present
    end

    context 'when event not found' do
      it 'returns not found' do
        post "/api/v1/devops/docker/hosts/#{host.id}/events/nonexistent-id/acknowledge",
             headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
