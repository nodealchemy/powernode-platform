# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::HousekeepingService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  def mcp_session(status:, expires_at:)
    McpSession.create!(
      user: user, account: account, session_token: SecureRandom.hex(16),
      status: status, expires_at: expires_at, last_activity_at: expires_at
    )
  end

  describe "#call session pruning" do
    it "deletes long-expired sessions and keeps fresh ones" do
      stale = mcp_session(status: "expired", expires_at: 3.days.ago)
      fresh = mcp_session(status: "active", expires_at: 1.hour.from_now)

      result = described_class.call

      expect(result[:sessions_deleted]).to be >= 1
      expect(McpSession.exists?(stale.id)).to be false
      expect(McpSession.exists?(fresh.id)).to be true
    end
  end

  describe "#call revoked-token pruning" do
    it "deletes tokens revoked beyond the retention window" do
      old = create(:oauth_access_token, :revoked)
      old.update_column(:revoked_at, 10.days.ago)

      expect { described_class.call }
        .to change { Doorkeeper::AccessToken.exists?(old.id) }.from(true).to(false)
    end

    it "keeps recently-revoked tokens (inside retention)" do
      recent = create(:oauth_access_token, :revoked)
      recent.update_column(:revoked_at, 1.day.ago)

      described_class.call
      expect(Doorkeeper::AccessToken.exists?(recent.id)).to be true
    end

    it "NEVER deletes a non-revoked token, even if its access token has expired" do
      # The row still carries a live refresh token — deleting it would force re-auth.
      live = create(:oauth_access_token, :expired) # expires_in 0, revoked_at nil
      live.update_column(:created_at, 30.days.ago)

      described_class.call
      expect(Doorkeeper::AccessToken.exists?(live.id)).to be true
    end
  end

  describe "#call orphaned DCR app pruning" do
    it "deletes an old DCR app with no non-revoked tokens" do
      app = create(:oauth_application, :mcp_client, created_at: 10.days.ago)
      revoked = create(:oauth_access_token, :revoked, oauth_app: app)
      revoked.update_column(:created_at, 10.days.ago)

      expect { described_class.call }
        .to change { OauthApplication.exists?(app.id) }.from(true).to(false)
    end

    it "keeps a DCR app that still has a non-revoked token (access-expired but refreshable)" do
      app = create(:oauth_application, :mcp_client, created_at: 10.days.ago)
      token = create(:oauth_access_token, :expired, oauth_app: app)
      token.update_column(:created_at, 10.days.ago)

      described_class.call
      expect(OauthApplication.exists?(app.id)).to be true
    end

    it "keeps a recently-registered DCR app" do
      app = create(:oauth_application, :mcp_client, created_at: 1.hour.ago)

      described_class.call
      expect(OauthApplication.exists?(app.id)).to be true
    end

    it "keeps a non-DCR application even with no tokens" do
      app = create(:oauth_application, created_at: 1.year.ago) # no mcp_dynamic_registration tag

      described_class.call
      expect(OauthApplication.exists?(app.id)).to be true
    end
  end

  describe "#call return summary" do
    it "returns counts for every pruned category" do
      expect(described_class.call).to match(
        hash_including(
          sessions_deleted: kind_of(Integer),
          access_tokens_deleted: kind_of(Integer),
          access_grants_deleted: kind_of(Integer),
          dcr_apps_deleted: kind_of(Integer)
        )
      )
    end
  end
end
