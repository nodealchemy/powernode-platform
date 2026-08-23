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
      def self.preview(params, deferred_operation: nil)
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
  #
  # STRENGTHENED under IMP-4a5094b22df0. Before it, this example was green for
  # a reason that had nothing to do with isolation: `Base.preview` hardcoded
  # `deferred_operation: nil`, so a preview could not see an operation at all
  # and the assertions were a statement about a method signature. That task
  # threads a context through on purpose, to anchor approval-card labels to the
  # account the gate opened the operation in — so the stub executors here reach
  # for the operation from their previews, and the examples pin what they can
  # and cannot get. The second one is the load-bearing one.
  describe "reveal-once isolation" do
    it "computing and re-reading the card preview never touches the deferred operation's one-shot reveal slot" do
      previewed_with = []
      stub_const("RevealIsolationSpecExecutor", Class.new do
        define_singleton_method(:preview) do |params, deferred_operation: nil|
          previewed_with << deferred_operation
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

      # The card path DID hand preview something. Without this the whole
      # example could pass by threading nothing — which is exactly how it used
      # to pass, and is no longer evidence of anything.
      expect(previewed_with).not_to be_empty
      # And what it handed over is NOT the operation. This is the guard: the
      # thing a preview holds carries the account it needs to scope a label
      # lookup and exposes no execution state to reach for.
      expect(previewed_with).to all(be_a(Ai::DeferredOperation::PreviewContext))
      expect(previewed_with).to all(satisfy { |ctx| ctx.account == account })
      expect(previewed_with).not_to include(executed_instance)

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

    # The load-bearing one. Threading an account into `preview` removed the
    # `deferred_operation: nil` that used to make this whole mistake class
    # self-limiting: an executor reaching for execution state from its preview
    # got NoMethodError on nil, and Ai::DeferredOperation#preview's rescue
    # degraded it to a generic card. Handing over the live operation instead
    # would have converted that loud failure into a silent success that renders
    # execution state — possibly reveal-once material — to an approver.
    #
    # So this example IS the fail-safe posture, stated as a test: an executor
    # that does the wrong thing must still produce a card with no secret in it.
    #
    # It dies against the threaded-`self` design, and the WAY it dies is the
    # point. There, `deferred_for`'s fresh instance means the reach returns nil
    # rather than the secret, so the secret-absence assertions above still pass
    # — and the card renders "Mint a thing " as though nothing were wrong. What
    # catches it is the degradation assertion below: the mistake stopped being
    # loud. That silence is the whole hazard, so the oracle has to be the
    # fallback text and not merely the absence of a string.
    it "degrades to a generic card, disclosing nothing, when an executor reaches for execution state in its preview" do
      stub_const("RevealGrabbingSpecExecutor", Class.new do
        # No respond_to? guard on purpose — the point is that this RAISES.
        def self.preview(params, deferred_operation: nil)
          { summary: "#{params['summary']} #{deferred_operation.take_revealed_result!}" }
        end

        def self.execute(_params, deferred_operation:)
          { minted_secret: "ONE-SHOT-SECRET" }
        end
      end)

      op = Ai::DeferredOperation.create!(
        account: account, action_category: "test.mint",
        executor_class: "RevealGrabbingSpecExecutor", params: { "summary" => "Mint a thing" }
      )
      executed_instance = Ai::DeferredOperation.find(op.id)
      executed_instance.execute_now!

      request = create(:ai_approval_request, account: account,
                       source_type: "Ai::DeferredOperation", source_id: op.id)
      step = request.step_statuses.first
      title = Ai::DeferredOperationApprovalContent.title(request, step)
      message = Ai::DeferredOperationApprovalContent.message(request, step)

      expect(title).not_to include("ONE-SHOT-SECRET")
      expect(message).not_to include("ONE-SHOT-SECRET")
      # Loud, not silent: the reach raised, Ai::DeferredOperation#preview's
      # rescue returned { summary: action_category, error: }, and the card
      # rendered that. Asserting the degraded text (rather than only the
      # secret's absence) is what distinguishes "the guard fired" from "the
      # executor happened to render nothing" — the confound that would make
      # this example vacuous.
      #
      # It is the bare category, NOT DeferredOperationApprovalContent.title's
      # "Approval needed: #{...}" arm: that arm is `preview[:summary].presence
      # || ...`, and the rescue's summary IS present, so the || never fires.
      expect(title).to eq("test.mint")

      # ...and the reach did not CONSUME the one-shot slot either, so the
      # legitimate reader still gets its single reveal.
      expect(executed_instance.take_revealed_result!).to eq(minted_secret: "ONE-SHOT-SECRET")
    end
  end

  # IMP-e75e843bd42b — the `approval_request_id` metadata key is the
  # PRODUCER'S declaration, and a content handler cannot clobber it.
  #
  # Ai::InterventionPolicyService#notification_limit_reached? excludes consent
  # traffic from the daily notification budget by exactly this key, on the
  # premise that notify_current_step! writes it unconditionally at the single
  # fan-out site. The base-metadata merge used to run `{base}.merge(handler)`,
  # so a SOURCE_HANDLERS provider echoing an `approval_request_id` key of its
  # own — a ubiquitous key in gate-result hashes, so an easy accident — would
  # silently overwrite the declaration and its fan-out would start counting
  # toward the budget again. The base keys name the request's own identity and
  # chain position; a handler customises CONTENT, never provenance.
  describe "handler metadata cannot clobber the fan-out's identity keys" do
    it "keeps the producer's approval_request_id when a handler emits its own" do
      stub_const("ClobberingApprovalContent", Class.new(Ai::DeferredOperationApprovalContent) do
        def self.metadata(_request)
          # The accident this pins against: a handler echoing a gate-result
          # hash whose approval_request_id is nil/foreign.
          { "approval_request_id" => nil, "custom_key" => "kept" }
        end
      end)
      described_class::SOURCE_HANDLERS["ClobberSpec::Source"] = "ClobberingApprovalContent"

      user = create(:user, account: account)
      request = create(:ai_approval_request, account: account,
                       source_type: "ClobberSpec::Source", source_id: SecureRandom.uuid)

      notification = Notification.find_by(account: account, user: user,
                                          notification_type: "autonomy_approval_required")
      expect(notification).to be_present
      expect(notification.metadata["approval_request_id"]).to eq(request.id)
      # The handler's non-colliding contribution still lands — base-wins is
      # scoped to the identity keys, not a rejection of handler metadata.
      expect(notification.metadata["custom_key"]).to eq("kept")
    ensure
      described_class::SOURCE_HANDLERS.delete("ClobberSpec::Source")
    end
  end
end
