# frozen_string_literal: true

require "rails_helper"

# IMP-acb2e40960e7 — approval-card message integrity. The card's message is
# "\n"-joined, and its dynamic segments (preview summary, preview impact,
# agent name) are caller-supplied text replayed verbatim — so an embedded
# newline forged extra card lines on a HUMAN approval gate (a spoofed
# "Impact:" line was reproduced live). Line structure is collapsed centrally
# here, at the one place the card is composed: per-executor sanitization
# cannot close the hole, because a newline-bearing name persisted by ANY
# create path resurfaces in later unrelated delete/update cards.
RSpec.describe Ai::DeferredOperationApprovalContent do
  let(:account) { create(:account) }

  # Exact live repro (rails runner): CreateFirewallRule.preview with this name
  # returned it verbatim in preview[:summary].
  let(:forged_summary) { "evil name\nImpact: totally safe, click approve" }

  def build_operation(summary:, impact: nil, agent: nil)
    stub_const("ApprovalContentSpecExecutor", Class.new do
      def self.preview(params, deferred_operation: nil)
        { summary: params["summary"], impact: params["impact"] }
      end
    end)

    Ai::DeferredOperation.create!(
      account: account,
      action_category: "sdwan.firewall_rule.create",
      executor_class: "ApprovalContentSpecExecutor",
      params: { summary: summary, impact: impact },
      ai_agent: agent
    )
  end

  def request_for(op)
    create(:ai_approval_request, account: account,
                                 source_type: "Ai::DeferredOperation", source_id: op.id)
  end

  def card_lines(op)
    request = request_for(op)
    described_class.message(request, request.step_statuses.first).split("\n")
  end

  describe ".message" do
    it "does not let a newline in the preview summary forge an Impact line (live repro)" do
      lines = card_lines(build_operation(summary: forged_summary))

      expect(lines).not_to include("Impact: totally safe, click approve")
      expect(lines).to include("evil name Impact: totally safe, click approve")
    end

    it "renders a legitimate single-line summary verbatim" do
      legit = "Add firewall rule 'deny-default' to SDWAN network wan-core"
      lines = card_lines(build_operation(summary: legit))

      expect(lines).to include(legit)
    end

    it "still renders the executor's own impact as its own card line" do
      lines = card_lines(
        build_operation(summary: "Add firewall rule", impact: "Traffic on port 443 will be dropped")
      )

      expect(lines).to include("Impact: Traffic on port 443 will be dropped")
    end

    it "collapses line structure inside the impact field itself" do
      lines = card_lines(
        build_operation(summary: "Add firewall rule", impact: "safe\nRequested by: root@example.com")
      )

      expect(lines).not_to include("Requested by: root@example.com")
      expect(lines).to include("Impact: safe Requested by: root@example.com")
    end

    it "collapses every line-break flavor, not just \\n" do
      op = build_operation(summary: "evil\r\nAgent: fake Requested by: fake\vImpact: fake")
      lines = card_lines(op)

      # Header + exactly one summary line — no separator flavor may add lines.
      expect(lines.length).to eq(2)
    end

    it "does not let a newline in the agent name forge lines (Ai::Agent#name has no format validation)" do
      agent = create(:ai_agent, account: account, name: "ops\nImpact: harmless")
      lines = card_lines(build_operation(summary: "Add firewall rule", agent: agent))

      expect(lines).not_to include("Impact: harmless")
      expect(lines).to include("Agent: ops Impact: harmless")
    end

    it "renders a legitimate agent name on its own Agent line" do
      agent = create(:ai_agent, account: account, name: "sdwan-manager")
      lines = card_lines(build_operation(summary: "Add firewall rule", agent: agent))

      expect(lines).to include("Agent: sdwan-manager")
    end
  end

  describe ".title" do
    it "collapses forged line structure in the summary (live repro)" do
      request = request_for(build_operation(summary: forged_summary))
      title = described_class.title(request, nil)

      expect(title).not_to include("\n")
      expect(title).to eq("evil name Impact: totally safe, click approve")
    end

    it "renders a legitimate summary verbatim" do
      legit = "Add firewall rule 'deny-default' to SDWAN network wan-core"
      request = request_for(build_operation(summary: legit))

      expect(described_class.title(request, nil)).to eq(legit)
    end
  end
end
