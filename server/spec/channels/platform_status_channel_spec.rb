# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A2 — who may listen to what.
RSpec.describe PlatformStatusChannel, type: :channel do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe "subscription" do
    before { stub_connection current_user: user }

    it "streams the account's own transitions and the shared stream alongside them" do
      subscribe(account_id: account.id)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("platform_status:#{account.id}")
      expect(subscription).to have_stream_from(described_class::SHARED_STREAM)
    end

    it "REJECTS a subscription to another account's stream" do
      other_account = create(:account)

      subscribe(account_id: other_account.id)

      expect(subscription).to be_rejected
      # `have_stream_from` raises "Must be subscribed!" on a rejected
      # subscription, so rejection IS the assertion — a rejected subscription
      # has no streams by construction.
      expect(subscription.streams).to be_empty
    end

    it "serves shared infrastructure alone when no account is named" do
      subscribe

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from(described_class::SHARED_STREAM)
      expect(subscription).not_to have_stream_from("platform_status:#{account.id}")
    end
  end

  describe "an unauthenticated connection" do
    before { stub_connection current_user: nil }

    it "is rejected for the shared stream too" do
      subscribe

      expect(subscription).to be_rejected
    end

    it "is rejected for an account stream" do
      subscribe(account_id: account.id)

      expect(subscription).to be_rejected
    end
  end

  describe "the publishing primitives" do
    it "routes an account-scoped transition to that account's stream" do
      expect { described_class.broadcast_transition(account.id, { type: "x" }) }
        .to have_broadcasted_to("platform_status:#{account.id}").exactly(:once)
    end

    it "routes a NULL-account transition to the shared stream, and not to an account's" do
      expect { described_class.broadcast_transition(nil, { type: "x" }) }
        .to have_broadcasted_to(described_class::SHARED_STREAM).exactly(:once)

      expect { described_class.broadcast_transition(nil, { type: "x" }) }
        .not_to have_broadcasted_to("platform_status:#{account.id}")
    end
  end
end
