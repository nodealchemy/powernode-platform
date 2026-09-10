# frozen_string_literal: true

require "rails_helper"

# IMP-01a04dac-1083 — the MCP-tool doors. ActivityMonitorTool's bulk
# notification ops update only the acting user's rows (user.notifications...),
# but published the resulting event to the ACCOUNT stream, whose client
# handlers mark every local row read (all-read) or clear the list (all-dismissed)
# — so an agent acting for one user wiped every coworker's bell.
#
# Each isolation example also asserts the op SUCCEEDED: a failed op broadcasts
# nothing, which would satisfy `not_to have_broadcasted_to` for the wrong reason.
RSpec.describe Ai::Tools::ActivityMonitorTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let!(:coworker) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:account_stream) { "account_#{account.id}" }

  def user_stream(u) = "notifications:user:#{u.id}"

  before { create(:notification, account: account, user: user) }

  {
    "mark_all_notifications_read" => "all_notifications_read",
    "dismiss_all_notifications" => "all_notifications_dismissed"
  }.each do |action, event|
    describe action do
      it "delivers #{event} to the acting user's own stream" do
        result = nil
        expect {
          result = tool.execute(params: { action: action })
        }.to have_broadcasted_to(user_stream(user)).with(hash_including(type: event))
        expect(result[:success]).to be(true)
      end

      it "keeps #{event} off the account stream and off a coworker" do
        result = nil
        expect {
          result = tool.execute(params: { action: action })
        }.not_to have_broadcasted_to(account_stream)
        expect(result[:success]).to be(true)

        expect {
          tool.execute(params: { action: action })
        }.not_to have_broadcasted_to(user_stream(coworker))
      end
    end
  end
end
