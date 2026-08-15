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
    it "renders byte-identical title and message to every approver in the step" do
      op = build_operation
      create_request(op, approver_count: 4)

      notifications = Notification.where(account: account, notification_type: "autonomy_approval_required")
      expect(notifications.count).to eq(4)
      expect(notifications.map(&:title).uniq.size).to eq(1)
      expect(notifications.map(&:message).uniq.size).to eq(1)
      expect(notifications.first.title).to include("Add firewall rule")
    end
  end
end
