# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpSession, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:session) { McpSession.create!(user: user, account: account) }

  # ===========================================================================
  # Associations
  # ===========================================================================
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:account) }
  end

  # ===========================================================================
  # Validations
  # ===========================================================================
  describe "validations" do
    subject { session }

    it { is_expected.to validate_presence_of(:session_token) }
    it { is_expected.to validate_uniqueness_of(:session_token) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[active expired revoked]) }

    it "is valid with valid attributes" do
      expect(session).to be_valid
    end
  end

  # ===========================================================================
  # Defaults (before_validation on create)
  # ===========================================================================
  describe "defaults on create" do
    it "auto-generates a session_token as UUID" do
      new_session = McpSession.create!(user: user, account: account)
      expect(new_session.session_token).to be_present
      expect(new_session.session_token).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it "sets expires_at to 24 hours from now" do
      freeze_time do
        new_session = McpSession.create!(user: user, account: account)
        expect(new_session.expires_at).to be_within(2.seconds).of(24.hours.from_now)
      end
    end

    it "sets last_activity_at to current time" do
      freeze_time do
        new_session = McpSession.create!(user: user, account: account)
        expect(new_session.last_activity_at).to be_within(2.seconds).of(Time.current)
      end
    end

    it "defaults status to 'active'" do
      new_session = McpSession.create!(user: user, account: account)
      expect(new_session.status).to eq("active")
    end

    it "does not overwrite explicitly set session_token" do
      custom_token = SecureRandom.uuid
      new_session = McpSession.create!(user: user, account: account, session_token: custom_token)
      expect(new_session.session_token).to eq(custom_token)
    end

    it "does not overwrite explicitly set expires_at" do
      custom_expiry = 48.hours.from_now
      new_session = McpSession.create!(user: user, account: account, expires_at: custom_expiry)
      expect(new_session.expires_at).to be_within(2.seconds).of(custom_expiry)
    end
  end

  # ===========================================================================
  # Scopes
  # ===========================================================================
  describe "scopes" do
    describe ".active" do
      it "returns sessions with status 'active' and expires_at in the future" do
        active_session = McpSession.create!(user: user, account: account, status: "active", expires_at: 1.hour.from_now)
        expired_session = McpSession.create!(user: user, account: account, status: "active", expires_at: 1.hour.ago, session_token: SecureRandom.uuid)
        revoked_session = McpSession.create!(user: user, account: account, status: "revoked", expires_at: 1.hour.from_now, session_token: SecureRandom.uuid)

        results = McpSession.active
        expect(results).to include(active_session)
        expect(results).not_to include(expired_session)
        expect(results).not_to include(revoked_session)
      end
    end

    describe ".expired" do
      it "returns sessions with status 'expired' or expires_at in the past" do
        active_session = McpSession.create!(user: user, account: account, status: "active", expires_at: 1.hour.from_now)
        status_expired = McpSession.create!(user: user, account: account, status: "expired", expires_at: 1.hour.from_now, session_token: SecureRandom.uuid)
        time_expired = McpSession.create!(user: user, account: account, status: "active", expires_at: 1.hour.ago, session_token: SecureRandom.uuid)

        results = McpSession.expired
        expect(results).to include(status_expired)
        expect(results).to include(time_expired)
        expect(results).not_to include(active_session)
      end
    end

    describe ".revoked" do
      it "returns sessions with status 'revoked'" do
        active_session = McpSession.create!(user: user, account: account, status: "active")
        revoked_session = McpSession.create!(user: user, account: account, status: "revoked", session_token: SecureRandom.uuid)

        results = McpSession.revoked
        expect(results).to include(revoked_session)
        expect(results).not_to include(active_session)
      end
    end

    describe ".for_account" do
      it "filters sessions by account_id" do
        other_account = create(:account)
        other_user = create(:user, account: other_account)
        session1 = McpSession.create!(user: user, account: account)
        session2 = McpSession.create!(user: other_user, account: other_account)

        results = McpSession.for_account(account.id)
        expect(results).to include(session1)
        expect(results).not_to include(session2)
      end
    end

    describe ".for_user" do
      it "filters sessions by user_id" do
        other_user = create(:user, account: account)
        session1 = McpSession.create!(user: user, account: account)
        session2 = McpSession.create!(user: other_user, account: account)

        results = McpSession.for_user(user.id)
        expect(results).to include(session1)
        expect(results).not_to include(session2)
      end
    end

    describe ".stale" do
      it "returns sessions with last_activity_at older than the given duration" do
        recent_session = McpSession.create!(user: user, account: account)
        stale_session = McpSession.create!(user: user, account: account, session_token: SecureRandom.uuid)
        stale_session.update_columns(last_activity_at: 2.hours.ago)

        results = McpSession.stale(1.hour)
        expect(results).to include(stale_session)
        expect(results).not_to include(recent_session)
      end

      it "defaults to 1 hour when no duration provided" do
        stale_session = McpSession.create!(user: user, account: account)
        stale_session.update_columns(last_activity_at: 2.hours.ago)

        results = McpSession.stale
        expect(results).to include(stale_session)
      end
    end
  end

  # ===========================================================================
  # Instance Methods
  # ===========================================================================
  describe "#revoke!" do
    it "sets status to 'revoked'" do
      session.revoke!
      expect(session.reload.status).to eq("revoked")
    end

    it "sets revoked_at to current time" do
      freeze_time do
        session.revoke!
        expect(session.reload.revoked_at).to be_within(2.seconds).of(Time.current)
      end
    end
  end

  describe "#touch_activity!" do
    it "updates last_activity_at via update_columns" do
      original_time = session.last_activity_at
      travel_to 1.hour.from_now do
        session.touch_activity!
        expect(session.reload.last_activity_at).to be > original_time
      end
    end

    it "does not change updated_at" do
      original_updated = session.updated_at
      travel_to 1.hour.from_now do
        session.touch_activity!
        expect(session.reload.updated_at).to eq(original_updated)
      end
    end
  end

  describe "#expired?" do
    it "returns true when status is 'expired'" do
      session.update!(status: "expired")
      expect(session.expired?).to be true
    end

    it "returns true when expires_at is in the past" do
      session.update_columns(expires_at: 1.hour.ago)
      expect(session.expired?).to be true
    end

    it "returns false when status is 'active' and expires_at is in the future" do
      expect(session.expired?).to be false
    end
  end

  describe "#active?" do
    it "returns true when status is 'active' and not expired" do
      expect(session.active?).to be true
    end

    it "returns false when status is 'revoked'" do
      session.update!(status: "revoked")
      expect(session.active?).to be false
    end

    it "returns false when expires_at is in the past" do
      session.update_columns(expires_at: 1.hour.ago)
      expect(session.active?).to be false
    end

    it "returns false when status is 'expired'" do
      session.update!(status: "expired")
      expect(session.active?).to be false
    end
  end

  describe "#revoked?" do
    it "returns true when status is 'revoked'" do
      session.update!(status: "revoked")
      expect(session.revoked?).to be true
    end

    it "returns false when status is 'active'" do
      expect(session.revoked?).to be false
    end
  end
end
