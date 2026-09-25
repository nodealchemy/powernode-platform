# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Containers', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'devops.containers.read' ]) }
  let(:headers) { auth_headers_for(user) }
  let(:template) { create(:devops_container_template, account: account) }

  describe 'GET /api/v1/devops/containers' do
    let!(:template_execution) { create(:devops_container_instance, account: account, template: template) }
    let!(:agent_sandbox) { create(:devops_container_instance, :sandbox, account: account, template: template) }

    it 'includes a sandbox flag on every listed instance' do
      get '/api/v1/devops/containers', headers: headers, as: :json

      items = JSON.parse(response.body)['data']['items']
      by_id = items.index_by { |i| i['id'] }
      expect(by_id[template_execution.id]['sandbox']).to eq(false)
      expect(by_id[agent_sandbox.id]['sandbox']).to eq(true)
    end

    context 'filtering on sandbox=true' do
      it 'returns only agent sandboxes' do
        # NOTE: `as: :json` combined with `params:` on a GET turns this into a
        # POST under this Rails version's integration test helper (params end
        # up JSON-encoded in the body, and the request is re-dispatched as a
        # write) — hits the 404 catch-all and masks the real assertion behind
        # a generic 500. Omit `as: :json`; render_success already returns JSON
        # regardless of Accept header on this API-only controller.
        get '/api/v1/devops/containers', params: { sandbox: 'true' }, headers: headers

        ids = JSON.parse(response.body)['data']['items'].map { |i| i['id'] }
        expect(ids).to include(agent_sandbox.id)
        expect(ids).not_to include(template_execution.id)
      end
    end

    context 'filtering on sandbox=false' do
      it 'returns only plain template executions' do
        get '/api/v1/devops/containers', params: { sandbox: 'false' }, headers: headers

        ids = JSON.parse(response.body)['data']['items'].map { |i| i['id'] }
        expect(ids).to include(template_execution.id)
        expect(ids).not_to include(agent_sandbox.id)
      end
    end

    it 'returns both when the sandbox filter is not given' do
      get '/api/v1/devops/containers', headers: headers, as: :json

      ids = JSON.parse(response.body)['data']['items'].map { |i| i['id'] }
      expect(ids).to include(template_execution.id, agent_sandbox.id)
    end
  end

  describe 'GET /api/v1/devops/containers/stats' do
    it 'counts paused instances separately (paused is not folded into active)' do
      create(:devops_container_instance, :paused, account: account, template: template)

      get '/api/v1/devops/containers/stats', headers: headers, as: :json

      stats = JSON.parse(response.body)['data']['stats']
      expect(stats['paused']).to eq(1)
    end
  end
end
