# frozen_string_literal: true

require "rails_helper"

# IMP-6858255cea72 — approval-card content de-duplication.
#
# Before this fix, `notify_current_step!` recomputed title/message/severity/
# metadata INSIDE the per-approver loop even though none of them depend on
# the approving user, and `DeferredOperationApprovalContent#title`/`#message`
# each independently re-ran the (DB-backed, post-cards-sweep) executor
# preview. Two deliberately separate, non-overlapping oracles below: one
# isolates the loop hoist (approver count must not affect content-computation
# count — proven via `.severity`, which never touches the preview memo), the
# other isolates the preview memoization (proven at N=1, where the loop shape
# is irrelevant and only the title/message double-call matters). Neither
# assertion alone would distinguish the two fixes from each other.
RSpec.describe Ai::ApprovalRequestNotifier do
  let(:account) { create(:account) }

  def build_operation(summary: "Add firewall rule 'deny-default' to SDWAN network wan-core")
    stub_const("NotifierSpecExecutor", Class.new do
      def self.preview(params)
        { summary: params["summary"] }
      end
    end)

    Ai::DeferredOperation.create!(
      account: account,
      action_category: "sdwan.firewall_rule.create",
      executor_class: "NotifierSpecExecutor",
      params: { "summary" => summary }
    )
  end

  # Triggers notify_current_step! via Ai::ApprovalRequest's after_create
  # callback (status defaults to "pending").
  def create_request(op, approver_count:)
    create_list(:user, approver_count, account: account)
    create(:ai_approval_request, account: account, source_type: "Ai::DeferredOperation", source_id: op.id)
  end

  describe "content computation is hoisted out of the per-approver loop" do
    it "computes step content once regardless of approver count, not once per approver" do
      op = build_operation
      severity_calls = 0
      allow(Ai::DeferredOperationApprovalContent).to receive(:severity).and_wrap_original do |m, *args|
        severity_calls += 1
        m.call(*args)
      end

      create_request(op, approver_count: 5)

      expect(severity_calls).to eq(1)
    end
  end

  describe "preview memoization" do
    it "computes the executor preview once per notification batch, not once per title/message call" do
      op = build_operation
      preview_calls = 0
      allow(NotifierSpecExecutor).to receive(:preview).and_wrap_original do |m, *args|
        preview_calls += 1
        m.call(*args)
      end

      create_request(op, approver_count: 1)

      expect(preview_calls).to eq(1)
    end
  end

  describe "N-approver identical content" do
    it "renders byte-identical title and message to approvers with materially different attributes" do
      op = build_operation
      # Deliberately NOT interchangeable fixture users — different names and
      # different permission sets — so this oracle actually has teeth: if a
      # future change threaded `user` into content computation (permission-
      # scoped redaction, per-approver formatting), this would catch it.
      # Today it can't vary: title/message/severity/metadata never receive
      # `user` at all (see approval_request_notifier.rb), so a memo that
      # collapses their per-approver recomputation collapses N identical
      # values, not N different ones.
      plain = create(:user, account: account, name: "Plain Approver")
      privileged = create(:user, account: account, name: "Admin Approver",
                                  permissions: %w[ai.autonomy.approve ai.agents.manage])

      request = create(:ai_approval_request, account: account,
                       source_type: "Ai::DeferredOperation", source_id: op.id)

      notifications = Notification.where(account: account, user: [plain, privileged],
                                          notification_type: "autonomy_approval_required")
      expect(notifications.count).to eq(2)
      expect(notifications.map(&:title).uniq.size).to eq(1)
      expect(notifications.map(&:message).uniq.size).to eq(1)
      expect(notifications.first.title).to include("Add firewall rule")
    end
  end

  # The team lead flagged two crypto-adjacent hazards this refactor could
  # trip: (1) a memo defeating a reveal-once secret slot's one-shot
  # semantics if the memoized value could transitively include it, and
  # (2) collapsing per-accessor variance if content legitimately differs by
  # approver. #2 is covered above (and is structurally impossible here —
  # no content method receives `user`). This covers #1 directly.
  describe "reveal-once isolation" do
    it "computing and re-reading the card preview never touches the deferred operation's one-shot reveal slot" do
      stub_const("RevealIsolationSpecExecutor", Class.new do
        def self.preview(params)
          { summary: params["summary"] }
        end

        def self.execute(_params, deferred_operation:)
          { minted_secret: "ONE-SHOT-SECRET" }
        end
      end)

      op = Ai::DeferredOperation.create!(
        account: account, action_category: "test.mint",
        executor_class: "RevealIsolationSpecExecutor", params: { "summary" => "Mint a thing" }
      )

      # Legitimately populate the one-shot slot on its own instance, mirroring
      # what Ai::ApprovalRequest#notify_source_of_decision does post-approval.
      executed_instance = Ai::DeferredOperation.find(op.id)
      executed_instance.execute_now!

      # Card content is computed (and memoized, via the fix under test) on an
      # ENTIRELY SEPARATE freshly-fetched instance — same as deferred_for
      # produces in production — after the mint has already happened.
      request = create(:ai_approval_request, account: account,
                       source_type: "Ai::DeferredOperation", source_id: op.id)
      step = request.step_statuses.first
      title = Ai::DeferredOperationApprovalContent.title(request, step)
      message_first = Ai::DeferredOperationApprovalContent.message(request, step)
      message_second = Ai::DeferredOperationApprovalContent.message(request, step)

      expect(title).not_to include("ONE-SHOT-SECRET")
      expect(message_first).not_to include("ONE-SHOT-SECRET")
      # The memo returns the same content on a second read — that's the fix
      # working as intended, not a leak: it is the pre-mint preview payload
      # both times, never the revealed secret.
      expect(message_second).to eq(message_first)

      # The slot itself is untouched by any preview/title/message call above
      # and still yields exactly once — proving the two channels never cross.
      expect(executed_instance.take_revealed_result!).to eq(minted_secret: "ONE-SHOT-SECRET")
      expect(executed_instance.take_revealed_result!).to be_nil
    end
  end
end
