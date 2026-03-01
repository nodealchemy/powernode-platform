# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Docker::Activities', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read) { create(:user, account: account, permissions: ['docker.activities.read']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }

  describe 'GET /api/v1/devops/docker/hosts/:host_id/activities' do
    let(:headers) { auth_headers_for(user_with_read) }

    before do
      create_list(:devops_docker_activity, 3, :completed, docker_host: host)
    end

    it 'returns list of activities' do
      get "/api/v1/devops/docker/hosts/#{host.id}/activities", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['items']).to be_an(Array)
      expect(response_data['data']['items'].length).to eq(3)
    end

    it 'includes pagination' do
      get "/api/v1/devops/docker/hosts/#{host.id}/activities", headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']['pagination']).to include(
        'current_page', 'per_page', 'total_pages', 'total_count'
      )
    end

    it 'filters by activity_type' do
      create(:devops_docker_activity, docker_host: host, activity_type: 'pull')

      get "/api/v1/devops/docker/hosts/#{host.id}/activities?activity_type=pull",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      types = response_data['data']['items'].map { |a| a['activity_type'] }
      expect(types.uniq).to eq(['pull'])
    end

    it 'filters by status' do
      create(:devops_docker_activity, :failed, docker_host: host)

      get "/api/v1/devops/docker/hosts/#{host.id}/activities?status=failed",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      statuses = response_data['data']['items'].map { |a| a['status'] }
      expect(statuses.uniq).to eq(['failed'])
    end

    it 'filters by container_id' do
      container = create(:devops_docker_container, docker_host: host)
      create(:devops_docker_activity, docker_host: host, container: container)

      get "/api/v1/devops/docker/hosts/#{host.id}/activities?container_id=#{container.id}",
          headers: headers, as: :json

      expect_success_response
    end

    it 'supports pagination params' do
      create_list(:devops_docker_activity, 5, docker_host: host)

      get "/api/v1/devops/docker/hosts/#{host.id}/activities?page=1&per_page=2",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['items'].length).to eq(2)
      expect(response_data['data']['pagination']['total_count']).to eq(8) # 3 from before + 5
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get "/api/v1/devops/docker/hosts/#{host.id}/activities", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/activities/:id' do
    let(:headers) { auth_headers_for(user_with_read) }
    let(:activity) { create(:devops_docker_activity, :completed, docker_host: host) }

    it 'returns activity details' do
      get "/api/v1/devops/docker/hosts/#{host.id}/activities/#{activity.id}", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['activity']['id']).to eq(activity.id)
      expect(response_data['data']['activity']['activity_type']).to eq(activity.activity_type)
    end

    context 'when activity not found' do
      it 'returns not found' do
        get "/api/v1/devops/docker/hosts/#{host.id}/activities/nonexistent-id", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
