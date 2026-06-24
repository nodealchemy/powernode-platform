# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Autonomy::ClaudeSessionDiscoveryService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, :mcp_client, account: account, status: "active") }
  subject(:service) { described_class.new(account: account) }

  def mcp_session(last_activity_at:)
    McpSession.create!(
      user: user,
      account: account,
      ai_agent: agent,
      status: "active",
      last_activity_at: last_activity_at
    )
  end

  describe "#most_recent_session" do
    it "returns the chronologically most-recent active session" do
      mcp_session(last_activity_at: 3.minutes.ago)
      newest = mcp_session(last_activity_at: 1.minute.ago)
      mcp_session(last_activity_at: 2.minutes.ago)

      expect(service.most_recent_session[:session_id]).to eq(newest.id)
    end

    # last_activity_at is nullable, and most_recent_session has no rescue. The
    # safety relies on active_sessions' `WHERE last_activity_at > ?` excluding any
    # NULL row (NULL > ts is never true). Force a true DB-level NULL (bypassing the
    # set_defaults create callback) to lock that guard in: if the activity-window
    # filter is ever relaxed, max_by over a nil string would raise and this fails.
    it "is nil-safe: rows with a NULL last_activity_at are excluded by the activity window" do
      newest = mcp_session(last_activity_at: 1.minute.ago)
      null_row = mcp_session(last_activity_at: 2.minutes.ago)
      null_row.update_columns(last_activity_at: nil)

      expect { service.most_recent_session }.not_to raise_error
      expect(service.most_recent_session[:session_id]).to eq(newest.id)
    end
  end
end
