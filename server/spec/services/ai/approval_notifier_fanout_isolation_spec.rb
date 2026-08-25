# frozen_string_literal: true

require "rails_helper"

# G5 / offer 01a03057-9425 — one bad handler silences the whole approval fan-out.
#
# `notify_current_step!` computes the card content ONCE, then loops the
# approvers creating notifications — and the entire method sits inside a single
# `rescue StandardError` that logs and returns. Three consequences, all silent:
#
#   1. A SOURCE_HANDLERS provider that raises in title/message/severity/metadata
#      aborts BEFORE the loop, so NOBODY is notified.
#   2. A provider returning a non-Hash from #metadata raises on .stringify_keys
#      with the same result.
#   3. A failure on ONE approver aborts the REMAINING approvers — a partial
#      fan-out where the operators who happen to sort later never hear.
#
# Why this matters more than an ordinary swallowed error: the thing being
# suppressed IS the operator obligation. An approval gate whose notification
# silently fails looks exactly like a gate nobody needed to act on, and the
# request sits pending forever. Notifications are the terminal function of the
# whole approve lane.
#
# ORACLES ARE ROWS. Each example asserts Notifications were actually created for
# the approvers who should have heard — never that a log line appeared.
RSpec.describe "approval fan-out isolation" do
  let(:account) { create(:account) }
  let!(:approvers) { create_list(:user, 3, account: account) }

  def operation
    stub_const("FanoutSpecExecutor", Class.new do
      def self.preview(params, deferred_operation: nil)
        { summary: params["summary"] }
      end
    end)

    Ai::DeferredOperation.create!(
      account: account,
      action_category: "sdwan.firewall_rule.create",
      executor_class: "FanoutSpecExecutor",
      params: { "summary" => "a change needing approval" }
    )
  end

  def notify!
    create(:ai_approval_request, account: account,
                                 source_type: "Ai::DeferredOperation",
                                 source_id: operation.id)
  end

  # Baseline: without a broken handler everyone hears. Without this the
  # examples below could pass because the fan-out never worked at all.
  it "notifies every approver on the happy path" do
    expect { notify! }.to change { Notification.count }.by(approvers.size)
  end

  context "when the content handler RAISES" do
    before do
      stub_const("ExplodingApprovalContent", Class.new do
        def self.notification_type = "autonomy_approval_required"
        def self.category = "ai"
        def self.action_url(_r) = "/app/notifications"
        def self.severity(_r) = "info"
        def self.title(_r, _s) = raise("handler blew up rendering the title")
        def self.message(_r, _s) = "m"
        def self.metadata(_r) = {}
      end)
      Ai::ApprovalRequestNotifier::SOURCE_HANDLERS["Ai::DeferredOperation"] =
        "ExplodingApprovalContent"
    end

    after { Ai::ApprovalRequestNotifier::SOURCE_HANDLERS.delete("Ai::DeferredOperation") }

    # The card is presentation. Failing to render a pretty title must not mean
    # the operator never learns a gate is pending.
    it "still notifies every approver, falling back to generic content" do
      expect { notify! }.to change { Notification.count }.by(approvers.size)
    end
  end

  context "when the content handler returns a non-Hash from #metadata" do
    before do
      stub_const("BadMetadataApprovalContent", Class.new do
        def self.notification_type = "autonomy_approval_required"
        def self.category = "ai"
        def self.action_url(_r) = "/app/notifications"
        def self.severity(_r) = "info"
        def self.title(_r, _s) = "t"
        def self.message(_r, _s) = "m"
        def self.metadata(_r) = "not a hash"
      end)
      Ai::ApprovalRequestNotifier::SOURCE_HANDLERS["Ai::DeferredOperation"] =
        "BadMetadataApprovalContent"
    end

    after { Ai::ApprovalRequestNotifier::SOURCE_HANDLERS.delete("Ai::DeferredOperation") }

    it "still notifies every approver" do
      expect { notify! }.to change { Notification.count }.by(approvers.size)
    end

    # The provenance keys are what the consent-budget exclusion reads
    # (IMP-e75e843bd42b), so they must survive a junk handler.
    it "still records approval_request_id on the notifications" do
      notify!

      expect(Notification.last.metadata["approval_request_id"]).to be_present
    end

    # DISCRIMINATING ORACLE. The two examples above are satisfied by EITHER fix:
    # coercing the junk metadata, or the handler-fallback catching the raise and
    # rendering generic content. Mutating the coercion away reddened nothing
    # until this existed.
    #
    # It also pins the better behaviour: junk in #metadata should cost the
    # handler its METADATA, not its whole card. A handler with a good title and
    # a bad metadata hash keeps the title.
    it "keeps the handler's own title rather than falling back wholesale" do
      notify!

      expect(Notification.last.title).to eq("t")
    end
  end

  context "when ONE approver's notification fails" do
    before do
      call = 0
      allow(Notification).to receive(:create_for_user).and_wrap_original do |orig, *args, **kw|
        call += 1
        raise "delivery failed for this approver" if call == 2

        orig.call(*args, **kw)
      end
    end

    # A partial fan-out is the nastiest shape: some operators hear, so the
    # request does not look abandoned, while the rest never do.
    it "does not starve the remaining approvers" do
      expect { notify! }.to change { Notification.count }.by(approvers.size - 1)
    end
  end
end
