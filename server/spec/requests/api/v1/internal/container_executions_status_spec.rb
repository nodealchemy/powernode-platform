# frozen_string_literal: true

require 'rails_helper'

# Focused on the fc-32 review guard: the internal status callback (fired by
# Gitea workflow steps) must not resurrect a paused sandbox into "running" —
# an operator paused it deliberately, and a stale/racing "running" callback
# from the workflow shouldn't silently override that. Not a full spec of
# ContainerExecutionsController.
RSpec.describe 'Api::V1::Internal::ContainerExecutions#status', type: :request do
  let(:account) { create(:account) }
  let(:template) { create(:devops_container_template, account: account) }

  let(:internal_worker) { create(:worker, account: account) }
  let(:headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  describe 'POST /api/v1/internal/container_executions/:execution_id/status' do
    it 'does not flip a paused instance to running' do
      instance = create(:devops_container_instance, :paused, account: account, template: template)

      post "/api/v1/internal/container_executions/#{instance.execution_id}/status",
           params: { status: 'running' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(instance.reload.status).to eq('paused')
    end

    it 'still starts a pending instance running' do
      instance = create(:devops_container_instance, :pending, account: account, template: template)

      post "/api/v1/internal/container_executions/#{instance.execution_id}/status",
           params: { status: 'running' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(instance.reload.status).to eq('running')
    end
  end
end
