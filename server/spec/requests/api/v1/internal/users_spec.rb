# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Users', type: :request do
  before do
    # Stub integrity service to avoid side-effect failures in audit log creation
    allow(Audit::LogIntegrityService).to receive(:apply_integrity).and_return(true)
  end

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account, email: 'test@example.com', name: 'Test User') }

  describe 'GET /api/v1/internal/users/:id' do
    context 'with valid service token' do
      it 'returns user details' do
        get "/api/v1/internal/users/#{user.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response_data

        expect(data['id']).to eq(user.id)
        expect(data['email']).to eq('test@example.com')
        expect(data['name']).to eq('Test User')
        expect(data).to include(
          'email_verified',
          'created_at',
          'last_login_at'
        )
      end

      it 'returns email_verified status' do
        user.update(email_verified_at: Time.current)

        get "/api/v1/internal/users/#{user.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        expect(json_response_data['email_verified']).to be true
      end
    end

    context 'with non-existent user' do
      it 'returns not found error' do
        get '/api/v1/internal/users/00000000-0000-0000-0000-000000000000',
            headers: internal_headers,
            as: :json

        expect_error_response('User not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/users/#{user.id}",
            as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/users/:user_id/anonymize' do
    # No phone shim. `users` has no `phone` column at all (confirmed against
    # db/schema.rb) — the controller must not reference it. IMP-7ff4be3454a6:
    # the old controller did `@user.update(phone: nil, ...)`, which raised
    # ActiveModel::UnknownAttributeError -> 500 on every anonymize call, so
    # every DataDeletionJob "full"/"anonymize" run failed at the final step.

    # Give the user real values in every field anonymize is supposed to clear,
    # so a passing assertion means the controller actually cleared it rather
    # than it merely defaulting to that value (mutation-proof: an assertion
    # against an already-nil field would still pass with the clearing code
    # deleted).
    before do
      user.enable_two_factor!
      user.generate_reset_token!
      # NOTE last_login_ip is deliberately NOT populated here: `encrypts
      # :last_login_ip` (user.rb) produces ciphertext that overflows the
      # column's `limit: 45` for any real IP string, so ANY write of a real
      # value — not just this spec's — raises PG::StringDataRightTruncation.
      # Grepping app/ confirms nothing in the app ever writes to this column
      # (only user_serialization.rb reads it); this is a pre-existing,
      # separate defect, out of this task's scope. Reported to the driver
      # rather than fixed here. The assertion below on last_login_ip is
      # therefore not mutation-proof (it is already nil by default).
      user.update!(
        preferences: { theme: 'dark' },
        # A key with no relation to any EXISTING redaction rule, deliberately:
        # {"email" => true} would pass the "does not archive..." audit-PII
        # assertion below even if notification_preferences were NEVER added
        # to #anonymize's audit_extra_redactions list at all —
        # ActiveSupport::ParameterFilter (the engine behind User's PRE-
        # EXISTING "email" filter_attributes entry) recurses into Hash
        # VALUES and masks any NESTED key matching a filtered name, so a
        # nested "email" key would incidentally get redacted for a reason
        # having nothing to do with the new per-instance mechanism this test
        # exists to cover — a regression in the new list would go
        # undetected. "digest"/"weekly" match no existing redaction rule.
        notification_preferences: { digest: 'weekly' },
        email_verification_token: 'verify-me-token',
        email_verification_sent_at: Time.current,
        email_verification_token_expires_at: 1.day.from_now,
        authorized_keys: [ 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP fixture@example.com' ]
      )
      user.reload
    end

    context 'with valid service token' do
      it 'clears every PII/credential field and sets status inactive' do
        original_password_digest = user.password_digest

        patch "/api/v1/internal/users/#{user.id}/anonymize",
              headers: internal_headers,
              as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('User anonymized successfully')

        user.reload
        expect(user.email).to eq("deleted_#{user.id}@anonymized.local")
        expect(user.name).to eq('Deleted User')
        expect(user.status).to eq('inactive')
        expect(user.password_digest).not_to eq(original_password_digest)
        # A FRESH User instance, not `user` itself: has_secure_password's
        # virtual `password` attribute is an in-memory ivar the factory set
        # at creation time (password { TestUsers::PASSWORD }); #reload only
        # refreshes DB-backed columns, so that ivar would otherwise still
        # read TestUsers::PASSWORD here — and #authenticate's failure branch
        # saves the record, which validates password reuse against
        # `password` when it's present, spuriously matching the password
        # history entry #track_password_change just wrote for the old
        # digest.
        expect(User.find(user.id).authenticate(TestUsers::PASSWORD)).to be false
        expect(user.two_factor_secret).to be_nil
        expect(user.two_factor_enabled).to be false
        expect(user.two_factor_enabled_at).to be_nil
        expect(user.backup_codes).to be_nil
        expect(user.two_factor_backup_codes_generated_at).to be_nil
        # NOT mutation-proof: `encrypts :last_login_ip` (user.rb) produces
        # ciphertext that overflows the column's `limit: 45` for any real IP
        # string, so this spec cannot seed a non-nil value to clear in the
        # first place (see the `before` block above) — pre-existing, out of
        # this task's scope, flagged separately. This assertion would pass
        # even with the clearing code deleted.
        expect(user.last_login_ip).to be_nil
        expect(user.preferences).to eq({})
        expect(user.notification_preferences).to eq({})
        expect(user.reset_token_digest).to be_nil
        expect(user.reset_token_expires_at).to be_nil
        expect(user.email_verification_token).to be_nil
        expect(user.email_verification_sent_at).to be_nil
        expect(user.email_verification_token_expires_at).to be_nil
        expect(user.authorized_keys).to eq([])
        expect(user.email_verified).to be false
        expect(user.email_verified_at).to be_nil
      end

      it 'deletes all password_histories, including the one the anonymize write itself creates' do
        # Seed pre-existing history (simulates past password changes) plus
        # confirm the anonymize write's OWN password change doesn't survive
        # either: #update! setting `password:` fires
        # PasswordSecurity#track_password_change, which writes the OUTGOING
        # digest (the user's REAL current password) into a fresh history row
        # (password_security.rb:148-163) — that row must not outlive this
        # request either, or the "erasure" leaves the real password's digest
        # behind under a different table.
        create_list(:password_history, 3, user: user)
        expect(user.password_histories.count).to eq(3)

        patch "/api/v1/internal/users/#{user.id}/anonymize",
              headers: internal_headers,
              as: :json

        expect_success_response
        expect(user.password_histories.count).to eq(0)
      end

      it 'sets status inactive and makes the original password unusable' do
        patch "/api/v1/internal/users/#{user.id}/anonymize",
              headers: internal_headers,
              as: :json
        expect_success_response

        # A FRESH User instance — see the comment on the same pattern above.
        reloaded = User.find(user.id)
        expect(reloaded.status).to eq('inactive')
        expect(reloaded.active?).to be false
        expect(reloaded.authenticate(TestUsers::PASSWORD)).to be false
      end

      it 'revokes an already-issued access token via the JWT blacklist, not merely via status' do
        # Minted BEFORE anonymize, while the user is still active — assert the
        # SPECIFIC mechanism (Security::JwtService.blacklisted?), not just
        # that a request with it later 401s, which the status check alone
        # would also produce.
        #
        # Minted a full minute in the past (travel_to), not merely "before" in
        # wall-clock call order: JwtBlacklistService's per-user marker revokes
        # a token only when its `iat` is STRICTLY EARLIER than the marker's
        # cutoff (token_predates_cutoff? uses `<`, not `<=`), so a token minted
        # in the SAME SECOND as the blacklist call — which two calls this
        # close together in a fast in-process spec reliably are — reads as NOT
        # revoked. That is a real, narrow same-second race in shared
        # production code (flagged to the driver separately, out of this
        # task's scope); sidestepping it here with travel_to keeps this
        # assertion about OUR code's use of the seam, not about that edge case.
        pre_anonymize_token = travel_to(1.minute.ago) { token_for(user) }
        expect(Security::JwtService.blacklisted?(pre_anonymize_token)).to be false

        patch "/api/v1/internal/users/#{user.id}/anonymize",
              headers: internal_headers,
              as: :json
        expect_success_response

        expect(Security::JwtService.blacklisted?(pre_anonymize_token)).to be true
      end

      it 'raises (fails the request) when JWT revocation fails, instead of reporting success' do
        allow(Security::JwtService).to receive(:blacklist_user_tokens).and_return(false)

        expect do
          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
        end.not_to raise_error # the controller action itself must not blow up the request process

        expect(response).to have_http_status(:internal_server_error)
        expect(json_response['success']).to eq(false)
      end

      it 'does not archive the real PII (preferences, authorized_keys, old email/name, ...) in the automatic audit row' do
        # The controller's own log_internal_audit("user.anonymize") row is the
        # intended record of this event; Auditable's automatic "updated" row
        # (fired by @user.update! via after_update) must not become a second,
        # unredacted copy of what anonymize exists to erase. This is now via
        # Auditable#audit_extra_redactions (per-instance, per-write), set by
        # the controller right before the update — NOT via User's global
        # filter_attributes, which stays exactly as it was (unchanged in this
        # diff — see spec/models/concerns/auditable_secret_redaction_spec.rb,
        # whose pinned "authorized_keys recorded in full" example for a
        # NORMAL (non-anonymize) update must stay green, and does).
        Auditable.with_logging do
          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
        end
        expect_success_response

        updated_rows = AuditLog.where(resource_type: 'User', resource_id: user.id, action: 'updated')
        expect(updated_rows).not_to be_empty

        updated_rows.each do |row|
          [ row.old_values, row.new_values ].each do |values|
            next if values.blank?

            json = values.to_json
            expect(json).not_to include('dark') # the seeded preferences value
            expect(json).not_to include('weekly') # the seeded notification_preferences value (no
            # relation to any pre-existing redaction rule — see the `before`
            # block comment for why this specific value was chosen)
            expect(json).not_to include('verify-me-token') # email_verification_token
            expect(json).not_to include('AAAAC3NzaC1lZDI1NTE5AAAAIP') # the seeded authorized_keys value
            # email/name are ALSO in this write's audit_extra_redactions list
            # (see the controller), but belt-and-braces: User's pre-existing
            # `encrypts`-driven global redaction already masks both on every
            # write, anonymize or not, so these two assertions would pass
            # even if the new per-instance list dropped them.
            expect(json).not_to include('test@example.com') # the user's pre-anonymize email
            expect(json).not_to include('Test User') # the user's pre-anonymize name
          end
        end
      end

      it 'writes an audit_logs row for the anonymize action itself' do
        # IMP-26a95cba1d43: log_internal_audit("user.anonymize", ...) was
        # never registered in AuditActions — AuditLog.create! raised
        # ActiveRecord::RecordInvalid and the rescue silently dropped the
        # row. Assert the row EXISTS with the exact action, not just 200.
        patch "/api/v1/internal/users/#{user.id}/anonymize",
              headers: internal_headers,
              as: :json

        expect_success_response
        expect(AuditLog.exists?(action: 'user.anonymize', resource_id: user.id)).to be true
      end

      it 'preserves user ID' do
        original_id = user.id

        patch "/api/v1/internal/users/#{user.id}/anonymize",
              headers: internal_headers,
              as: :json

        expect_success_response
        user.reload
        expect(user.id).to eq(original_id)
      end
    end

    context 'with non-existent user' do
      it 'returns not found error' do
        patch '/api/v1/internal/users/00000000-0000-0000-0000-000000000000/anonymize',
              headers: internal_headers,
              as: :json

        expect_error_response('User not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/users/#{user.id}/anonymize",
              as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/users/:user_id/anonymize_audit_logs' do
    context 'with valid service token' do
      let!(:audit_logs) do
        [
          create(:audit_log, user: user, ip_address: '192.168.1.1', user_agent: 'Mozilla/5.0'),
          create(:audit_log, user: user, ip_address: '10.0.0.1', user_agent: 'Chrome/90.0')
        ]
      end

      it 'anonymizes audit log data' do
        patch "/api/v1/internal/users/#{user.id}/anonymize_audit_logs",
              headers: internal_headers,
              as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('User audit logs anonymized')

        audit_logs.each do |log|
          log.reload
          expect(log.ip_address).to eq('0.0.0.0')
          expect(log.user_agent).to eq('anonymized')
        end

        expect(AuditLog.exists?(action: 'user.anonymize_audit_logs', resource_id: user.id)).to be true
      end

      it 'does not affect other users audit logs' do
        other_user = create(:user, account: account)
        other_log = create(:audit_log, user: other_user, ip_address: '192.168.2.1')

        patch "/api/v1/internal/users/#{user.id}/anonymize_audit_logs",
              headers: internal_headers,
              as: :json

        expect_success_response
        other_log.reload
        expect(other_log.ip_address).to eq('192.168.2.1')
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/users/#{user.id}/anonymize_audit_logs",
              as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'DELETE /api/v1/internal/users/:user_id/consents' do
    context 'with valid service token' do
      let!(:consents) do
        [
          create(:user_consent, user: user, account: account),
          create(:user_consent, user: user, account: account)
        ]
      end

      it 'deletes all user consents' do
        expect do
          delete "/api/v1/internal/users/#{user.id}/consents",
                 headers: internal_headers,
                 as: :json
        end.to change { UserConsent.where(user_id: user.id).count }.from(2).to(0)

        expect_success_response
        expect(json_response_data['message']).to eq('Deleted 2 consent records')
        expect(AuditLog.exists?(action: 'user.delete_consents', resource_id: user.id)).to be true
      end

      it 'does not affect other users consents' do
        other_user = create(:user, account: account)
        other_consent = create(:user_consent, user: other_user, account: account)

        delete "/api/v1/internal/users/#{user.id}/consents",
               headers: internal_headers,
               as: :json

        expect_success_response
        expect(UserConsent.exists?(other_consent.id)).to be true
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        delete "/api/v1/internal/users/#{user.id}/consents",
               as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'DELETE /api/v1/internal/users/:user_id/terms_acceptances' do
    context 'with valid service token' do
      it 'returns success message with count' do
        delete "/api/v1/internal/users/#{user.id}/terms_acceptances",
               headers: internal_headers,
               as: :json

        expect_success_response
        expect(json_response_data['message']).to match(/Deleted \d+ terms acceptance records/)
        expect(AuditLog.exists?(action: 'user.delete_terms_acceptances', resource_id: user.id)).to be true
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        delete "/api/v1/internal/users/#{user.id}/terms_acceptances",
               as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'DELETE /api/v1/internal/users/:user_id/password_histories' do
    context 'with valid service token' do
      it 'returns success message with count' do
        delete "/api/v1/internal/users/#{user.id}/password_histories",
               headers: internal_headers,
               as: :json

        expect_success_response
        expect(json_response_data['message']).to match(/Deleted \d+ password history records/)
        expect(AuditLog.exists?(action: 'user.delete_password_histories', resource_id: user.id)).to be true
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        delete "/api/v1/internal/users/#{user.id}/password_histories",
               as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'DELETE /api/v1/internal/users/:user_id/roles' do
    context 'with valid service token' do
      let!(:role) { create(:role) }
      let!(:user_role) { UserRole.create!(user: user, role: role) }

      it 'deletes all user roles' do
        # User has default member role (from after_create callback) + the explicit role
        initial_count = user.user_roles.count

        delete "/api/v1/internal/users/#{user.id}/roles",
               headers: internal_headers,
               as: :json

        expect_success_response
        expect(user.user_roles.count).to eq(0)
        expect(AuditLog.exists?(action: 'user.delete_roles', resource_id: user.id)).to be true
      end

      it 'does not affect other users roles' do
        other_user = create(:user, account: account)
        UserRole.create!(user: other_user, role: role)

        delete "/api/v1/internal/users/#{user.id}/roles",
               headers: internal_headers,
               as: :json

        expect_success_response
        expect(UserRole.where(user: other_user, role: role)).to exist
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        delete "/api/v1/internal/users/#{user.id}/roles",
               as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end
end
