# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, status: "active") }

  describe "happy path with a fresh access token" do
    it "connects and identifies the user" do
      tokens = Security::JwtService.generate_user_tokens(user)
      connect "/cable?token=#{tokens[:access_token]}"
      expect(connection.current_user).to eq(user)
    end

    it "does NOT mint replacement tokens when the access token was already valid" do
      tokens = Security::JwtService.generate_user_tokens(user)
      connect "/cable?token=#{tokens[:access_token]}&refresh_token=#{tokens[:refresh_token]}"

      expect(connection.instance_variable_get(:@minted_tokens)).to be_nil
    end
  end

  describe "rejection" do
    it "rejects when no token is supplied" do
      expect { connect "/cable" }.to have_rejected_connection
    end

    it "rejects when the access token is invalid garbage" do
      expect { connect "/cable?token=not.a.real.jwt" }.to have_rejected_connection
    end

    it "rejects when neither access nor refresh decodes" do
      expect { connect "/cable?token=bogus.jwt&refresh_token=also.bogus" }
        .to have_rejected_connection
    end
  end

  describe "expired access + valid refresh" do
    it "mints fresh tokens and accepts the connection" do
      tokens = Security::JwtService.generate_user_tokens(user)

      # Travel past access TTL but stay within refresh TTL — JwtService.decode
      # will raise on access (Signature has expired), the Connection falls back
      # to the refresh token, mints fresh tokens, and authenticates.
      travel_to(2.hours.from_now) do
        connect "/cable?token=#{tokens[:access_token]}&refresh_token=#{tokens[:refresh_token]}"
      end

      expect(connection.current_user).to eq(user)
    end

    it "stashes the freshly-minted tokens for transmit" do
      tokens = Security::JwtService.generate_user_tokens(user)

      travel_to(2.hours.from_now) do
        connect "/cable?token=#{tokens[:access_token]}&refresh_token=#{tokens[:refresh_token]}"
      end

      minted = connection.instance_variable_get(:@minted_tokens)
      expect(minted).to be_present
      expect(minted[:access_token]).to be_present
      expect(minted[:refresh_token]).to be_present
      expect(minted[:access_token]).not_to eq(tokens[:access_token])
    end
  end

  describe "standalone refresh-only path" do
    it "accepts a refresh_token without an access token and stashes minted tokens" do
      tokens = Security::JwtService.generate_user_tokens(user)

      connect "/cable?refresh_token=#{tokens[:refresh_token]}"

      expect(connection.current_user).to eq(user)
      minted = connection.instance_variable_get(:@minted_tokens)
      expect(minted).to be_present
      expect(minted[:access_token]).to be_present
    end

    it "rejects when the refresh token is itself invalid" do
      expect { connect "/cable?refresh_token=not.a.real.refresh" }
        .to have_rejected_connection
    end
  end

  describe "maintenance mode" do
    before do
      Admin::MaintenanceMode.enable!(message: "Upgrading")
      Admin::MaintenanceMode.invalidate_cache!
    end

    # N2: a maintenance-mode block closes with a distinct reason
    # (reason: "maintenance_mode", reconnect: false) rather than JUST raising
    # reject_unauthorized_connection's UnauthorizedError — see
    # Connection#reject_for_maintenance! for why (a WebSocketManager
    # reconnect-storm bug on the frontend: reason: "unauthorized" specifically
    # is misread as an expired session). It STILL calls
    # reject_unauthorized_connection right after, though (LOW item 6: #connect
    # must not return normally for a connection with no user) — so
    # have_rejected_connection matches here exactly as it did before N2.
    it "rejects a plain user's JWT connection" do
      tokens = Security::JwtService.generate_user_tokens(user)
      expect { connect "/cable?token=#{tokens[:access_token]}" }.to have_rejected_connection
    end

    it "rejects a plain user's legacy UserToken connection" do
      minted = UserToken.create_token_for_user(user, type: "access")
      expect { connect "/cable?token=#{minted[:token]}" }.to have_rejected_connection
    end

    # `connect "/cable?..."` (the DSL helper above) runs through
    # ActionCable::Connection::TestCase's TestConnection module, which never
    # sets @coder/@websocket — close_for_maintenance!'s test-safety guard
    # means the real #close is never reached that way, so asserting on it
    # needs a lower-level instance built by hand instead, with @coder set so
    # the real branch runs and #close is actually invoked.
    it "calls #close with the distinct maintenance_mode reason, not just reject_unauthorized_connection" do
      conn = ApplicationCable::Connection.allocate
      allow(conn).to receive(:request).and_return(double(remote_ip: "203.0.113.5")) # rubocop:disable RSpec/VerifiedDoubles
      allow(conn).to receive(:logger).and_return(double(error: nil, info: nil, warn: nil)) # rubocop:disable RSpec/VerifiedDoubles
      conn.instance_variable_set(:@coder, ActiveSupport::JSON)

      expect(conn).to receive(:close).with(reason: "maintenance_mode", reconnect: false)
      expect { conn.send(:reject_for_maintenance!, user) }
        .to raise_error(ActionCable::Connection::Authorization::UnauthorizedError)
    end

    it "still connects a system.admin user" do
      admin = create(:user, account: account, status: "active", permissions: [ "system.admin" ])
      tokens = Security::JwtService.generate_user_tokens(admin)

      connect "/cable?token=#{tokens[:access_token]}"

      expect(connection.current_user).to eq(admin)
    end

    it "still connects an admin.maintenance.mode holder" do
      admin = create(:user, account: account, status: "active", permissions: [ "admin.maintenance.mode" ])
      tokens = Security::JwtService.generate_user_tokens(admin)

      connect "/cable?token=#{tokens[:access_token]}"

      expect(connection.current_user).to eq(admin)
    end

    it "does not gate the mTLS worker arm" do
      worker = create(:worker, :system_worker, status: "active")
      mtls_header = { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")) }

      connect "/cable", headers: mtls_header

      expect(connection.current_worker).to eq(worker)
    end

    it "connects normally again once maintenance mode is disabled" do
      Admin::MaintenanceMode.disable!
      Admin::MaintenanceMode.invalidate_cache!

      tokens = Security::JwtService.generate_user_tokens(user)
      connect "/cable?token=#{tokens[:access_token]}"

      expect(connection.current_user).to eq(user)
    end

  end

  # Dropped for this round (review decision): cable had no impersonation
  # support before N2 either — an impersonation JWT hit the generic
  # "Invalid token type" branch and was rejected outright. A prior draft
  # added real impersonation-JWT support so the impersonator exemption could
  # apply on cable too, but that's new auth surface with real gaps (checked
  # only at connect, not on every subsequent action; identified_by :impersonator
  # collided with the anonymize disconnect key) for a benefit nobody asked
  # for. This pins the ORIGINAL behavior: impersonation tokens are rejected.
  describe "impersonation tokens are rejected on cable, same as any other unrecognized type" do
    it "rejects an impersonation-typed JWT outright" do
      admin = create(:user, account: account, status: "active", permissions: [ "system.admin" ])
      session = ImpersonationSession.create_session!(impersonator: admin, impersonated_user: user)
      payload = {
        type: "impersonation", session_id: session.id, sub: user.id,
        account_id: user.account_id, version: Security::JwtService::CURRENT_TOKEN_VERSION
      }
      token = Security::JwtService.encode(payload)

      expect { connect "/cable?token=#{token}" }.to have_rejected_connection
    end
  end

  describe "mTLS worker arm" do
    let(:worker) { create(:worker, :system_worker, status: "active") }
    let(:mtls_header) do
      { "X-Forwarded-Tls-Client-Cert-Info" =>
        CGI.escape(%(Subject="CN=#{worker.node_instance_id}")) }
    end

    it "identifies an active worker by mTLS subject CN" do
      connect "/cable", headers: mtls_header
      expect(connection.current_worker).to eq(worker)
      expect(connection.current_user).to be_nil
    end

    it "ignores any token query param when an mTLS header is also present" do
      tokens = Security::JwtService.generate_user_tokens(user)
      connect "/cable?token=#{tokens[:access_token]}", headers: mtls_header
      expect(connection.current_worker).to eq(worker)
      expect(connection.current_user).to be_nil
    end

    it "rejects when the mTLS CN does not resolve to a worker" do
      bad_headers = { "X-Forwarded-Tls-Client-Cert-Info" =>
        CGI.escape(%(Subject="CN=#{SecureRandom.uuid}")) }
      expect { connect "/cable", headers: bad_headers }.to have_rejected_connection
    end
  end
end
