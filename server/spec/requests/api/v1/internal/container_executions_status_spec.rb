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

    # The paused guard used to be check-then-act on the in-memory row: a pause
    # committed between find_instance and start_running! was overwritten. The
    # stale copy below stands in for that window — the row is paused in the
    # database, but the controller's loaded object still says provisioning.
    it 'does not resurrect a sandbox paused after the instance was loaded' do
      instance = create(:devops_container_instance, :provisioning, account: account, template: template)
      stale = Devops::ContainerInstance.find(instance.id)
      instance.update_column(:status, 'paused')
      allow(Devops::ContainerInstance).to receive(:find_by!).and_return(stale)

      post "/api/v1/internal/container_executions/#{instance.execution_id}/status",
           params: { status: 'running' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(instance.reload.status).to eq('paused')
    end

    # start_running! stamps started_at, which is the reaper's timeout clock;
    # a repeated "running" callback must not restart the budget.
    it 'does not reset started_at when a running instance gets another running callback' do
      original_start = 2.hours.ago.change(usec: 0)
      instance = create(:devops_container_instance, :running, account: account, template: template,
                         started_at: original_start)

      post "/api/v1/internal/container_executions/#{instance.execution_id}/status",
           params: { status: 'running' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(instance.reload.started_at).to eq(original_start)
    end

    it 'does not move a paused instance back to provisioning on a stale provisioning callback' do
      instance = create(:devops_container_instance, :paused, account: account, template: template)

      post "/api/v1/internal/container_executions/#{instance.execution_id}/status",
           params: { status: 'provisioning' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(instance.reload.status).to eq('paused')
    end

    it 'still moves a pending instance to provisioning' do
      instance = create(:devops_container_instance, :pending, account: account, template: template)

      post "/api/v1/internal/container_executions/#{instance.execution_id}/status",
           params: { status: 'provisioning' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(instance.reload.status).to eq('provisioning')
    end
  end
end
