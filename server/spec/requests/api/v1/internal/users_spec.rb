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
        # wall-clock call order. The same-second boundary this comment used to
        # describe as a live gap is now CLOSED (IMP-c358bba8bdc8):
        # token_predates_cutoff? uses `<=`, so a token minted in the SAME
        # SECOND as the blacklist call is correctly revoked too. The
        # backdating here is kept anyway, not to dodge a live bug but for
        # INDEPENDENCE: this test exists to pin OUR code's use of the
        # blacklist seam, not the seam's own boundary behavior (which
        # jwt_blacklist_service_spec.rb now covers directly, including the
        # same-second case) — a full minute keeps this assertion meaningful
        # regardless of which side of any future boundary change it lands on.
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

      # IMP-df4aa2b46dbc finding 1 — an API key this user created kept
      # authenticating indefinitely after erasure (ApiKey#active? has zero
      # coupling to created_by/user status). Driven through the REAL
      # authenticator (Api::V1::A2aController#authenticate_api_key), not
      # asserted on the `is_active` column — a column assertion would still
      # pass with the auth-path fix reverted, since it wouldn't be exercising
      # the credential at all.
      describe 'API keys created by the erased user' do
        let(:other_user) { create(:user, account: account) }
        let!(:own_api_key) { create(:api_key, account: account, created_by: user, is_active: true) }
        let!(:other_users_api_key) { create(:api_key, account: account, created_by: other_user, is_active: true) }

        # Stubs only the downstream skill handler, never authenticate_api_key
        # itself — the authenticator (the thing under test) runs for real.
        #
        # Rack::Attack disabled around the call: unrelated pre-existing defect
        # (rack_attack.rb's own extract_account_from_request/safelist query
        # ApiKey by a `key_hash` column that does not exist on this table —
        # schema only has `key_digest` — raising PG::UndefinedColumn and
        # poisoning the request's DB transaction for every subsequent query,
        # including the real authenticate_api_key lookup this test exists to
        # exercise). Also confirmed separately: the app's own
        # `unless Rails.env.test?` guard around installing this middleware is
        # dead — the rack-attack GEM's own Railtie installs it unconditionally
        # in every environment regardless of that guard, so it runs in this
        # test process too. Flagged to the driver as its own finding; toggling
        # `enabled` here only isolates this spec from it, not a fix.
        def a2a_auth_error_code(key_value)
          handler = instance_double(A2a::MessageHandler, list_tasks: { result: { tasks: [] } })
          allow(A2a::MessageHandler).to receive(:new).and_return(handler)

          original_rack_attack_enabled = Rack::Attack.enabled
          Rack::Attack.enabled = false
          begin
            post '/api/v1/a2a',
                 params: { jsonrpc: '2.0', id: '1', method: 'tasks/list', params: {} }.to_json,
                 headers: { 'X-API-Key' => key_value, 'Content-Type' => 'application/json' }
          ensure
            Rack::Attack.enabled = original_rack_attack_enabled
          end

          JSON.parse(response.body)['error']&.dig('code')
        end

        it 'is refused by the real A2A authenticator after erasure' do
          key_value = own_api_key.key_value
          expect(a2a_auth_error_code(key_value)).to be_nil # sanity: authenticates BEFORE erasure

          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
          expect_success_response

          expect(a2a_auth_error_code(key_value)).to eq(-32001)
        end

        it "does not revoke another user's key (scoped by created_by_id, which cannot reach another user's key by construction)" do
          other_key_value = other_users_api_key.key_value

          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
          expect_success_response

          expect(a2a_auth_error_code(other_key_value)).to be_nil
        end

        # Blocker 2, review round 2: last_used_ip is the same PII class
        # already scrubbed on user_tokens/mcp_sessions — an already-inactive
        # key must not be skipped just because it isn't also being
        # deactivated by this request.
        it 'scrubs last_used_ip even on a key that was already inactive before erasure' do
          already_inactive_key = create(
            :api_key, account: account, created_by: user, is_active: false, last_used_ip: '203.0.113.7'
          )

          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
          expect_success_response

          expect(ApiKey.find(already_inactive_key.id).last_used_ip).to be_nil
        end

        # Deliberate retention (review round 2, non-blocking): allowed_ips is
        # IP infrastructure the key's CREATOR configured the key to run
        # from, not a record of this user's own activity — scrubbing it
        # would destroy configuration history for no privacy benefit once
        # the key is already deactivated.
        it 'retains allowed_ips as key configuration, not user PII' do
          own_api_key.update!(allowed_ips: [ '203.0.113.0/24' ])

          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
          expect_success_response

          expect(ApiKey.find(own_api_key.id).allowed_ips).to eq([ '203.0.113.0/24' ])
        end
      end

      # IMP-df4aa2b46dbc finding 4 — none of these are touched by
      # anonymize-in-place today (dependent: :destroy on User only fires on
      # an actual user.destroy!, which this design never calls). Every
      # assertion reads a FRESH row from the DB, not the in-memory object.
      describe 'ancillary PII tables' do
        let!(:user_token) do
          UserToken.create!(
            user: user,
            token_digest: SecureRandom.hex(32),
            token_type: 'access',
            name: "Everett's Laptop",
            last_used_ip: '203.0.113.5',
            user_agent: 'RedFirst/1.0'
          )
        end

        let!(:mcp_session) do
          McpSession.create!(
            account: account,
            user: user,
            session_token: SecureRandom.hex(16),
            ip_address: '203.0.113.9',
            user_agent: 'RedFirst/2.0',
            display_name: "Everett's Laptop",
            client_info: { hostname: 'everett-laptop.local' },
            metadata: { device_id: 'abc123' },
            status: 'active'
          )
        end

        let(:other_user) { create(:user, account: account) }
        let!(:impersonation_as_impersonator) do
          create(:impersonation_session, impersonator: user, impersonated_user: other_user)
        end
        let!(:impersonation_as_target) do
          create(:impersonation_session, impersonator: other_user, impersonated_user: user)
        end
        let!(:notification) { create(:notification, account: account, user: user) }

        it 'revokes and scrubs the PII on the erased user_tokens row' do
          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
          expect_success_response

          reloaded = UserToken.find(user_token.id)
          expect(reloaded.revoked).to be true
          expect(reloaded.last_used_ip).to be_nil
          expect(reloaded.user_agent).to be_nil
          expect(reloaded.name).to be_nil
        end

        # Non-blocking 4 split (review round 2): a row already revoked for a
        # real, different reason must not have that history overwritten just
        # because its PII also needs scrubbing.
        it "preserves an already-revoked token's original revocation metadata while still scrubbing its PII" do
          original_time = 3.days.ago.change(usec: 0)
          user_token.update!(revoked: true, revoked_at: original_time, revoked_reason: 'manual')

          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
          expect_success_response

          reloaded = UserToken.find(user_token.id)
          expect(reloaded.revoked_at).to be_within(1.second).of(original_time)
          expect(reloaded.revoked_reason).to eq('manual')
          expect(reloaded.last_used_ip).to be_nil
          expect(reloaded.user_agent).to be_nil
          expect(reloaded.name).to be_nil
        end

        # Blocker 2, review round 3: `revoked` is a NULLABLE boolean.
        # `where(revoked: false)` and `where(revoked: true)` BOTH exclude a
        # NULL row in SQL — a normal revoked/unrevoked pair cannot reproduce
        # this, it needs the NULL value specifically (raw update_column,
        # bypassing the model default).
        it 'scrubs a user_token whose revoked column is NULL, not just false or true' do
          user_token.update_column(:revoked, nil)

          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
          expect_success_response

          reloaded = UserToken.find(user_token.id)
          expect(reloaded.revoked).to be true
          expect(reloaded.last_used_ip).to be_nil
          expect(reloaded.user_agent).to be_nil
          expect(reloaded.name).to be_nil
        end

        it 'revokes and scrubs the PII on the erased mcp_sessions row' do
          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
          expect_success_response

          reloaded = McpSession.find(mcp_session.id)
          expect(reloaded.status).to eq('revoked')
          expect(reloaded.ip_address).to be_nil
          expect(reloaded.user_agent).to be_nil
          expect(reloaded.display_name).to be_nil
          expect(reloaded.client_info).to eq({})
          expect(reloaded.metadata).to eq({})
        end

        # Round 3 parity with the UserToken history-preservation test above:
        # the mcp_sessions update was ALSO split into two update_all calls
        # (round 3, replacing round 2's incorrect update! rationale) to
        # avoid clobbering an existing revoked_at.
        it "preserves an already-revoked mcp_session's original revoked_at while still scrubbing its PII" do
          original_time = 3.days.ago.change(usec: 0)
          mcp_session.update_columns(status: 'revoked', revoked_at: original_time)

          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
          expect_success_response

          reloaded = McpSession.find(mcp_session.id)
          expect(reloaded.revoked_at).to be_within(1.second).of(original_time)
          expect(reloaded.ip_address).to be_nil
          expect(reloaded.user_agent).to be_nil
          expect(reloaded.display_name).to be_nil
          expect(reloaded.client_info).to eq({})
          expect(reloaded.metadata).to eq({})
        end

        it 'scrubs ip_address/user_agent on a session where the erased user was the IMPERSONATOR' do
          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
          expect_success_response

          reloaded = ImpersonationSession.find(impersonation_as_impersonator.id)
          expect(reloaded.ip_address).to be_nil
          expect(reloaded.user_agent).to be_nil
        end

        it "leaves a session where the erased user was only the TARGET untouched (not this user's PII)" do
          original_ip = impersonation_as_target.ip_address
          original_agent = impersonation_as_target.user_agent

          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
          expect_success_response

          reloaded = ImpersonationSession.find(impersonation_as_target.id)
          expect(reloaded.ip_address).to eq(original_ip)
          expect(reloaded.user_agent).to eq(original_agent)
        end

        it 'deletes the erased user\'s notifications' do
          expect do
            patch "/api/v1/internal/users/#{user.id}/anonymize",
                  headers: internal_headers,
                  as: :json
          end.to change { Notification.where(id: notification.id).count }.from(1).to(0)

          expect_success_response
        end
      end

      # IMP-df4aa2b46dbc finding 3 — a live ActionCable connection was never
      # forced closed on erasure. Asserted on the REAL broadcast reaching the
      # exact internal channel a live connection with this identity would be
      # subscribed to (computed via ActionCable's own RemoteConnection, not
      # hand-typed), with the real disconnect payload — not a mock of
      # `remote_connections`/`disconnect` being called.
      it 'broadcasts a disconnect over the real ActionCable internal channel for this user' do
        channel = ActionCable.server.remote_connections
          .where(current_user: user, current_worker: nil)
          .send(:internal_channel)

        # Pins the expected channel to a value computed INDEPENDENTLY of
        # RemoteConnection (review round 2, reviewer note): the line above
        # proves this test's own computation matches production's, but both
        # would silently drift together if a THIRD identified_by were added
        # to ApplicationCable::Connection — this literal closes that gap.
        expect(channel).to eq("action_cable/#{user.to_gid_param}")

        expect do
          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
        end.to have_broadcasted_to(channel).with(hash_including('type' => 'disconnect'))

        expect_success_response
      end

      # Blocker 1, review round 2: before this fix, the disconnect sat AFTER
      # the JWT-revocation raise — any blacklist_user_tokens failure left the
      # already-committed erasure with the live socket still open
      # indefinitely, since nothing after the raise ever ran.
      it 'still disconnects the live ActionCable connection even when JWT revocation fails' do
        allow(Security::JwtService).to receive(:blacklist_user_tokens).and_return(false)

        channel = ActionCable.server.remote_connections
          .where(current_user: user, current_worker: nil)
          .send(:internal_channel)

        expect do
          patch "/api/v1/internal/users/#{user.id}/anonymize",
                headers: internal_headers,
                as: :json
        end.to have_broadcasted_to(channel).with(hash_including('type' => 'disconnect'))

        expect(response).to have_http_status(:internal_server_error)
      end

      # Review round 3: distinct from the test above. This app's own
      # rescue_from StandardError (api_response.rb:201) already logs
      # exception.message for ANY unhandled exception, so a single JWT
      # failure alone is not sensitive to the added Rails.logger.error line
      # — the framework's generic handler already surfaces that message
      # (verified: a spec asserting the log line on the single-failure case
      # alone passed even with the line removed). The line's actual
      # contribution only shows up here, where the disconnect ALSO raises:
      # Ruby's `ensure` semantics mean the DISCONNECT's exception is what
      # ultimately propagates and reaches rescue_from, not the JWT one — so
      # without the explicit log line, "Failed to revoke JWTs" is lost
      # entirely, and only the disconnect's own (Redis-shaped) message
      # survives.
      it 'logs the original JWT failure even when the disconnect broadcast itself also raises' do
        allow(Security::JwtService).to receive(:blacklist_user_tokens).and_return(false)
        remote_connections_double = instance_double(ActionCable::RemoteConnections)
        allow(ActionCable.server).to receive(:remote_connections).and_return(remote_connections_double)
        allow(remote_connections_double).to receive(:where).and_raise(StandardError, 'redis unreachable')
        allow(Rails.logger).to receive(:error).and_call_original

        patch "/api/v1/internal/users/#{user.id}/anonymize",
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(Rails.logger).to have_received(:error).with(a_string_matching(/Failed to revoke JWTs/)).at_least(:once)
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
        # IMP-b33a3ecca331 (S5): the response now also carries `data: {count:}`
        # (Compliance::DataDeletionJob reads it back), so json_response_data
        # returns that data hash rather than falling back to the whole
        # envelope — read `message` from the full response.
        expect(json_response['message']).to eq('Deleted 2 consent records')
        expect(json_response_data['count']).to eq(2)
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
