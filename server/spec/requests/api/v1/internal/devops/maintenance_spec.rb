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
    it 'reconciles a paused sandbox stuck past the pause timeout' do
      stale_paused = create(:devops_container_instance, :paused, account: account, template: template,
                             updated_at: 3.hours.ago)

      post '/api/v1/internal/devops/maintenance/reconcile_instances', headers: headers

      expect(response).to have_http_status(:ok)
      expect(stale_paused.reload.status).not_to eq("paused")
      json = JSON.parse(response.body)
      expect(json['data']['reconciled_count']).to be >= 1
    end

    it 'leaves a recently-paused sandbox alone' do
      recent_paused = create(:devops_container_instance, :paused, account: account, template: template,
                              updated_at: 5.minutes.ago)

      post '/api/v1/internal/devops/maintenance/reconcile_instances', headers: headers

      expect(recent_paused.reload.status).to eq("paused")
    end
  end
end
