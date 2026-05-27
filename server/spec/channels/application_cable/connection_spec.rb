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
