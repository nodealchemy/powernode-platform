# frozen_string_literal: true

require 'rails_helper'

# IMP-b719328ddeb9 — the completion-notice address snapshot is exposed to the
# worker by exactly one read (the internal show), is scrubbed by the write that
# completes the row, and is absent from every other serializer.
RSpec.describe 'GDPR completion notification address', type: :request do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, :owner, account: account) }
  let(:user) { create(:user, account: account) }

  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  before do
    allow(Audit::LogIntegrityService).to receive(:apply_integrity).and_return(true)
    allow(AuditLog).to receive(:log_compliance_event).and_return(true)
    allow(AuditLog).to receive(:log_action).and_return(true)
    allow(NotificationService).to receive(:send_email).and_return(true)
    allow(Notification).to receive(:create).and_return(Notification.new)
    allow(WorkerJobService).to receive(:system_worker_jwt).and_return('test-jwt-token')
    allow_any_instance_of(WorkerJobService).to receive(:make_worker_request).and_return({ 'job_id' => 'test' })
  end

  def anonymize!(target)
    target.update_columns(email: "deleted_#{target.id}@anonymized.local")
  end

  describe 'data deletion requests' do
    let!(:deletion_request) do
      create(:data_management_deletion_request, account: account, user: user, status: 'processing',
                                                processing_started_at: Time.current)
    end
    let(:snapshot) { deletion_request.notification_email }
    let(:url) { "/api/v1/internal/data_deletion_requests/#{deletion_request.id}" }

    it 'returns the snapshot on the internal show, still after the user email is erased' do
      snapshot
      anonymize!(user)

      get url, headers: internal_headers, as: :json

      expect(json_response_data['data_deletion_request']['notification_email']).to eq(snapshot)
    end

    it 'does not return the snapshot from the write responses' do
      patch url, params: { status: 'processing' }, headers: internal_headers, as: :json

      expect(response.body).not_to include(snapshot)
    end

    it 'scrubs the snapshot when the worker completes the request, and does not echo it' do
      snapshot
      patch url, params: { status: 'completed', completed_at: Time.current.iso8601, deletion_log: [] },
                 headers: internal_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(snapshot)
      expect(deletion_request.reload.status).to eq('completed')
      expect(deletion_request.notification_email).to be_nil
    end

    it 'sends the complete_request notice to the snapshot after the user email is erased' do
      snapshot
      anonymize!(user)

      patch url, params: { action_type: 'complete', deletion_log: [] }, headers: internal_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(NotificationService).to have_received(:send_email)
        .with(hash_including(template: 'data_deletion_completed', email: snapshot))
      expect(NotificationService).not_to have_received(:send_email).with(hash_including(user_id: user.id))
      expect(deletion_request.reload.notification_email).to be_nil
    end

    it 'completes without sending, and warns, when the row has no snapshot' do
      deletion_request.update_columns(notification_email: nil)
      allow(Rails.logger).to receive(:warn)

      patch url, params: { action_type: 'complete', deletion_log: [] }, headers: internal_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(deletion_request.reload.status).to eq('completed')
      expect(NotificationService).not_to have_received(:send_email)
        .with(hash_including(template: 'data_deletion_completed'))
      expect(Rails.logger).to have_received(:warn).with(/no notification address/i)
    end

    context 'with the data subject endpoints' do
      let(:headers) { auth_headers_for(user) }

      it 'does not put the snapshot in the privacy deletion status or dashboard' do
        snapshot

        get '/api/v1/privacy/deletion', headers: headers, as: :json
        expect(response.body).not_to include('notification_email')
        expect(response.body).not_to include(snapshot)

        get '/api/v1/privacy/dashboard', headers: headers, as: :json
        expect(response.body).not_to include('notification_email')
      end
    end
  end

  describe 'account terminations' do
    let!(:termination) do
      Account::Termination.create!(account: account, requested_by: owner, status: 'processing',
                                   requested_at: 31.days.ago, grace_period_ends_at: 1.day.ago,
                                   processing_started_at: 1.hour.ago)
    end
    let(:snapshot) { termination.notification_email }
    let(:url) { "/api/v1/internal/account_terminations/#{termination.id}" }

    it 'returns the snapshot on the internal show, still after the owner is anonymized' do
      snapshot
      anonymize!(owner)

      get url, headers: internal_headers, as: :json

      expect(json_response_data['notification_email']).to eq(snapshot)
    end

    it 'does not return the snapshot from the list' do
      snapshot
      get '/api/v1/internal/account_terminations', headers: internal_headers, as: :json

      expect(response.body).not_to include(snapshot)
    end

    it 'scrubs the snapshot when the worker completes the termination, and does not echo it' do
      snapshot
      patch url, params: { status: 'completed', completed_at: Time.current.iso8601 },
                 headers: internal_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(snapshot)
      expect(termination.reload.status).to eq('completed')
      expect(termination.notification_email).to be_nil
    end
  end
end
