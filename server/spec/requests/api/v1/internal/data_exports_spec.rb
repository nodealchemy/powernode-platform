# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::DataExports', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:subscription) { create(:subscription, account: account) }

  before do
    skip 'Business billing module not loaded' unless defined?(Billing::Invoice) && defined?(Billing::Subscription)

    allow(Audit::LogIntegrityService).to receive(:apply_integrity).and_return(true)
    allow(AuditLog).to receive(:log_action).and_return(true)
  end

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  describe 'GET /api/v1/internal/users/:user_id/export/profile' do
    context 'with internal authentication' do
      it 'returns user profile data' do
        get "/api/v1/internal/users/#{user.id}/export/profile", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to include(
          'id' => user.id,
          'email' => user.email
        )
      end

      it 'includes user timestamps' do
        get "/api/v1/internal/users/#{user.id}/export/profile", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('created_at')
      end
    end

    context 'when user does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/users/00000000-0000-0000-0000-000000000000/export/profile', headers: internal_headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/users/#{user.id}/export/profile", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/internal/users/:user_id/export/audit_logs' do
    before do
      create_list(:audit_log, 3, user: user, account: account)
    end

    context 'with internal authentication' do
      it 'returns user audit logs' do
        get "/api/v1/internal/users/#{user.id}/export/audit_logs", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to be_an(Array)
        expect(data.length).to eq(3)
      end

      it 'includes audit log details' do
        get "/api/v1/internal/users/#{user.id}/export/audit_logs", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data
        first_log = data.first

        expect(first_log).to include('id', 'action', 'resource_type')
      end
    end
  end

  describe 'GET /api/v1/internal/users/:user_id/export/consents' do
    context 'with internal authentication' do
      it 'returns user consents' do
        get "/api/v1/internal/users/#{user.id}/export/consents", headers: internal_headers, as: :json

        expect_success_response
        # No consents exist for this user, so controller returns empty data
        data = json_response['data']
        expect(data).to be_nil.or be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/internal/accounts/:account_id/export/payments' do
    before do
      # Payments are accessed via account.payments; invoices via account.invoices (through subscription)
      3.times do
        invoice = create(:invoice, account: account, subscription: subscription)
        create(:payment, invoice: invoice, account: account)
      end
    end

    context 'with internal authentication' do
      it 'returns account payments' do
        get "/api/v1/internal/accounts/#{account.id}/export/payments", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to be_an(Array)
        expect(data.length).to eq(3)
      end

      it 'includes payment details' do
        get "/api/v1/internal/accounts/#{account.id}/export/payments", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data
        first_payment = data.first

        expect(first_payment).to include('id', 'amount', 'currency', 'status')
      end
    end

    context 'when account does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/accounts/00000000-0000-0000-0000-000000000000/export/payments', headers: internal_headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/internal/accounts/:account_id/export/invoices' do
    before do
      create_list(:invoice, 3, account: account, subscription: subscription)
    end

    context 'with internal authentication' do
      it 'returns account invoices' do
        get "/api/v1/internal/accounts/#{account.id}/export/invoices", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to be_an(Array)
        expect(data.length).to eq(3)
      end

      it 'includes invoice details with a total_amount sourced from the money total' do
        get "/api/v1/internal/accounts/#{account.id}/export/invoices", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data
        first_invoice = data.first

        expect(first_invoice).to include('id', 'invoice_number', 'status', 'total_amount')
        expect(first_invoice['total_amount']).not_to be_nil
      end
    end
  end

  describe 'GET /api/v1/internal/accounts/:account_id/export/subscriptions' do
    context 'with internal authentication' do
      it 'returns account subscriptions' do
        # Ensure account has a subscription so the controller returns non-empty data
        subscription

        get "/api/v1/internal/accounts/#{account.id}/export/subscriptions", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(data.length).to be >= 1
        expect(data.first).to include('id', 'plan_id', 'status', 'started_at')
      end
    end
  end
end

RSpec.describe 'Api::V1::Internal::DataExports (core-mode account exports)', type: :request do
  let(:account) { create(:account) }

  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  before do
    skip 'Business billing module is loaded; core-mode guard is not exercised' if defined?(Billing::Invoice)

    allow(AuditLog).to receive(:log_action).and_return(true)
  end

  describe 'GET /api/v1/internal/accounts/:account_id/export/payments' do
    it 'reports the provider as unavailable instead of an account with no records' do
      get "/api/v1/internal/accounts/#{account.id}/export/payments", headers: internal_headers, as: :json

      expect_success_response
      expect(json_response['data']).to eq([])
      expect(json_response['meta']).to include('available' => false, 'reason' => 'no_export_provider_installed')
    end
  end

  describe 'GET /api/v1/internal/accounts/:account_id/export/invoices' do
    it 'reports the provider as unavailable instead of an account with no records' do
      get "/api/v1/internal/accounts/#{account.id}/export/invoices", headers: internal_headers, as: :json

      expect_success_response
      expect(json_response['data']).to eq([])
      expect(json_response['meta']).to include('available' => false, 'reason' => 'no_export_provider_installed')
    end
  end

  describe 'GET /api/v1/internal/accounts/:account_id/export/subscriptions' do
    it 'reports the provider as unavailable instead of an account with no records' do
      get "/api/v1/internal/accounts/#{account.id}/export/subscriptions", headers: internal_headers, as: :json

      expect_success_response
      expect(json_response['data']).to eq([])
      expect(json_response['meta']).to include('available' => false, 'reason' => 'no_export_provider_installed')
    end
  end
end

# IMP-8aab38f3ad62 — GDPR Article 15 subject-access export. Runs in every mode
# (no billing skip): the two endpoints below are core, and the block above is
# skipped wholesale in core mode, which is how an always-empty files export and
# an always-empty activity export survived with green specs.
RSpec.describe 'Api::V1::Internal::DataExports (subject-access files and activity)', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:storage) { create(:file_storage, account: account) }

  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  before do
    allow(AuditLog).to receive(:log_action).and_return(true)
  end

  describe 'GET /api/v1/internal/accounts/:account_id/export/files' do
    let!(:subject_file) do
      create(:file_object, account: account, storage: storage, uploaded_by: user, filename: 'subject-contract.pdf')
    end

    def export_files(for_account: account, user_id: user.id)
      get "/api/v1/internal/accounts/#{for_account.id}/export/files",
          params: { user_id: user_id }, headers: internal_headers
    end

    it "contains the data subject's file" do
      export_files

      expect_success_response
      ids = json_response_data.map { |f| f['id'] }
      expect(ids).to include(subject_file.id)
      exported = json_response_data.find { |f| f['id'] == subject_file.id }
      expect(exported).to include(
        'filename' => 'subject-contract.pdf',
        'content_type' => subject_file.content_type,
        'file_size' => subject_file.file_size
      )
      expect(json_response['meta']).to include('count' => 1)
    end

    it "includes a soft-deleted file the platform still holds, marked with deleted_at" do
      subject_file.update_columns(deleted_at: 1.day.ago)

      export_files

      exported = json_response_data.find { |f| f['id'] == subject_file.id }
      expect(exported).to be_present
      expect(exported['deleted_at']).to be_present
    end

    it "does not include another account's files" do
      other_account = create(:account)
      other_user = create(:user, account: other_account)
      other_storage = create(:file_storage, account: other_account)
      foreign = create(:file_object, account: other_account, uploaded_by: other_user, storage: other_storage)
      # A row in account B that names the subject as uploader: only the
      # account_id key keeps it out, so this pins that key on its own.
      foreign_by_subject = create(:file_object, account: other_account, uploaded_by: user, storage: other_storage)

      export_files

      ids = json_response_data.map { |f| f['id'] }
      expect(ids).to include(subject_file.id)
      expect(ids).not_to include(foreign.id, foreign_by_subject.id)
    end

    it "does not include a co-member's files: the export is the subject's, not the account's" do
      co_member = create(:user, account: account)
      co_member_file = create(:file_object, account: account, storage: storage, uploaded_by: co_member)

      export_files

      ids = json_response_data.map { |f| f['id'] }
      expect(ids).to include(subject_file.id)
      expect(ids).not_to include(co_member_file.id)
    end

    it 'rejects a request that names no data subject' do
      get "/api/v1/internal/accounts/#{account.id}/export/files", headers: internal_headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "answers 404 for a user who is not a member of the account" do
      other_account = create(:account)
      outsider = create(:user, account: other_account)
      create(:file_object, account: other_account, uploaded_by: outsider,
                           storage: create(:file_storage, account: other_account))

      export_files(user_id: outsider.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  # There is no per-user activity model to export: the per-user trail is
  # AuditLog, already exported by export/audit_logs. The endpoint that answered
  # an always-empty success is removed rather than kept as a duplicate.
  describe 'GET /api/v1/internal/users/:user_id/export/activity' do
    it 'is no longer routed' do
      get "/api/v1/internal/users/#{user.id}/export/activity", headers: internal_headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
