# frozen_string_literal: true

require 'rails_helper'

# Focused on the paused-sandbox sweep added for the fc-32 review (paused was
# never reconciled at all — a stuck sandbox stayed "paused" forever). Not a
# full spec of MaintenanceController#reconcile_instances.
RSpec.describe 'Api::V1::Internal::Devops::Maintenance', type: :request do
  let(:account) { create(:account) }
  let(:template) { create(:devops_container_template, account: account) }

  # Internal API authenticates via mTLS: InternalBaseController includes
  # MtlsClientAuthentication and resolves the worker from the client-cert
  # subject CN forwarded by the reverse proxy. Specs simulate that by
  # setting the X-Forwarded-Tls-Client-Cert-Info header directly.
  let(:internal_worker) { create(:worker, account: account) }
  let(:headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  describe 'POST /api/v1/internal/devops/maintenance/reconcile_instances' do
    # fc-32 review: the original sweep keyed off `updated_at`, which
    # `record_resource_usage` bumps on every metrics report — an actively-
    # reported paused sandbox could reset its own reap clock forever. It now
    # uses the SAME budget the running sweep already enforces
    # (`started_at + timeout_seconds`), so pausing never grants extra time
    # and reporting resource usage while paused can't extend it either.
    it 'reaps a paused sandbox once started_at + timeout_seconds has passed, ending it as "timeout"' do
      stale_paused = create(:devops_container_instance, :paused, account: account, template: template,
                             started_at: 2.hours.ago, timeout_seconds: 3600, updated_at: 1.minute.ago)

      post '/api/v1/internal/devops/maintenance/reconcile_instances', headers: headers

      expect(response).to have_http_status(:ok)
      expect(stale_paused.reload.status).to eq("timeout")
      json = JSON.parse(response.body)
      expect(json['data']['timed_out_count']).to be >= 1
    end

    it 'leaves a paused sandbox alone while it is still within its timeout budget, even with a stale updated_at' do
      within_budget_paused = create(:devops_container_instance, :paused, account: account, template: template,
                                     started_at: 5.minutes.ago, timeout_seconds: 3600, updated_at: 3.hours.ago)

      post '/api/v1/internal/devops/maintenance/reconcile_instances', headers: headers

      expect(within_budget_paused.reload.status).to eq("paused")
    end

    it 'never reaps a paused sandbox with no timeout_seconds set, mirroring the running sweep' do
      no_budget_paused = create(:devops_container_instance, :paused, account: account, template: template,
                                 started_at: 1.year.ago, timeout_seconds: nil)

      post '/api/v1/internal/devops/maintenance/reconcile_instances', headers: headers

      expect(no_budget_paused.reload.status).to eq("paused")
    end
  end
end
