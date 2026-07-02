# frozen_string_literal: true

require "rails_helper"

# inc6: escalation audit surface + benefit measurement on Ai::ModelRouterService
# (RoutingAnalytics concern). Escalations are RoutingDecisions whose persisted
# rationale marks decision == "escalate"; the controlled comparison cohort is
# standard-tier selections of the SAME complexity level (from the linked
# Ai::TaskComplexityAssessment).
RSpec.describe Ai::ModelRouterService, "escalation analytics" do
  subject(:service) { described_class.new(account: account) }

  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  # --- helpers -------------------------------------------------------------

  def escalate_rationale(level:, task_type:, effort:, score: 0.72, tier: "reasoning")
    {
      "decision" => "escalate",
      "summary" => "escalate standard→#{tier} (#{level} #{score})",
      "target_tier" => tier,
      "baseline_tier" => "standard",
      "baseline_model" => "claude-sonnet-5",
      "delivered_model" => tier == "frontier" ? "claude-fable-5" : "claude-opus-4-8",
      "effort" => effort,
      "complexity" => {
        "level" => level, "score" => score, "task_type" => task_type,
        "top_signals" => [ { "signal" => "token_count", "value" => 1200.0 } ]
      },
      "policy_version" => "1.0.0"
    }
  end

  def held_rationale(level:, task_type:, kind: "baseline")
    {
      "decision" => kind,
      "summary" => "#{kind} standard→standard (#{level})",
      "target_tier" => "standard",
      "baseline_tier" => "standard",
      "delivered_model" => "claude-sonnet-5",
      "effort" => "high",
      "complexity" => { "level" => level, "score" => 0.4, "task_type" => task_type, "top_signals" => [] },
      "policy_version" => "1.0.0"
    }
  end

  def escalated_decision(level: "complex", task_type: "code_generation", effort: "xhigh",
                         tier: "reasoning", outcome_trait: :successful, acct: account, assessment: nil,
                         seam: nil, latency_ms: nil)
    rationale = escalate_rationale(level: level, task_type: task_type, effort: effort, tier: tier)
    rationale = rationale.merge("latency_seam" => seam) if seam
    attrs = { account: acct, model_tier: tier, complexity_assessment: assessment,
              request_metadata: { "agent_id" => "agent-1", "agent_type" => "code_assistant", "effort" => effort },
              rationale: rationale }
    attrs[:actual_latency_ms] = latency_ms if latency_ms
    create(:ai_routing_decision, outcome_trait, **attrs)
  end

  def standard_decision(level: "complex", task_type: "code_generation", kind: "baseline",
                        outcome_trait: :successful, acct: account, assessment: nil,
                        seam: nil, latency_ms: nil)
    rationale = held_rationale(level: level, task_type: task_type, kind: kind)
    rationale = rationale.merge("latency_seam" => seam) if seam
    attrs = { account: acct, model_tier: "standard", complexity_assessment: assessment,
              request_metadata: { "agent_id" => "agent-2", "agent_type" => "code_assistant" },
              rationale: rationale }
    attrs[:actual_latency_ms] = latency_ms if latency_ms
    create(:ai_routing_decision, outcome_trait, **attrs)
  end

  def assessment_for(level: "complex", task_type: "code_generation")
    trait = level == "expert" ? :expert : :complex
    create(:ai_task_complexity_assessment, trait, account: account,
           complexity_level: level, task_type: task_type)
  end

  # =========================================================================
  # (a1) escalation_decisions listing
  # =========================================================================
  describe "#escalation_decisions" do
    it "returns an empty array when there are no decisions (clean empty state)" do
      expect(service.escalation_decisions).to eq([])
    end

    it "lists only escalation-marked decisions, newest first" do
      escalated_decision(task_type: "code_generation")
      standard_decision # not an escalation
      escalated_decision(task_type: "reasoning", tier: "frontier", effort: "max")

      result = service.escalation_decisions
      expect(result.size).to eq(2)
      expect(result.map { |d| d[:task_type] }).to contain_exactly("code_generation", "reasoning")
    end

    it "does not leak other accounts' escalations" do
      escalated_decision(acct: other_account)
      expect(service.escalation_decisions).to eq([])
    end

    it "exposes the rationale summary, top signals, tier, effort, and cost outcome" do
      escalated_decision(tier: "reasoning", effort: "xhigh")
      row = service.escalation_decisions.first

      expect(row).to include(
        model_tier: "reasoning", effort: "xhigh", baseline_tier: "standard",
        delivered_model: "claude-opus-4-8", task_type: "code_generation",
        complexity_level: "complex", agent_type: "code_assistant", outcome: "succeeded"
      )
      expect(row[:rationale_summary]).to include("escalate")
      expect(row[:top_signals]).to be_present
      expect(row[:cost_usd]).to be_within(0.0001).of(0.0008)
    end

    it "filters by tier" do
      escalated_decision(tier: "reasoning")
      escalated_decision(tier: "frontier", task_type: "reasoning")

      expect(service.escalation_decisions(tier: "frontier").map { |d| d[:model_tier] }).to eq([ "frontier" ])
    end

    it "honors the time window" do
      old = escalated_decision
      old.update_column(:created_at, 40.days.ago)
      escalated_decision(task_type: "analysis")

      recent = service.escalation_decisions(time_range: 7.days)
      expect(recent.map { |d| d[:task_type] }).to eq([ "analysis" ])
    end

    it "caps the number of rows returned" do
      3.times { escalated_decision }
      expect(service.escalation_decisions(limit: 2).size).to eq(2)
    end
  end

  # =========================================================================
  # (a2) escalation_rollup
  # =========================================================================
  describe "#escalation_rollup" do
    it "returns clean zeros with no decisions (no division by zero)" do
      rollup = service.escalation_rollup

      expect(rollup[:total_decisions]).to eq(0)
      expect(rollup[:escalated_decisions]).to eq(0)
      expect(rollup[:spend][:escalated_share_pct]).to eq(0.0)
      expect(rollup[:selections]).to include(frontier: 0, reasoning: 0, high_effort: 0)
      expect(rollup[:advisory][:recommend_tightening]).to be(false)
    end

    it "counts frontier / reasoning / high-effort selections" do
      escalated_decision(tier: "reasoning", effort: "xhigh")
      escalated_decision(tier: "frontier", effort: "max", task_type: "reasoning")
      standard_decision

      rollup = service.escalation_rollup
      expect(rollup[:selections][:frontier]).to eq(1)
      expect(rollup[:selections][:reasoning]).to eq(1)
      expect(rollup[:selections][:high_effort]).to eq(2)
      expect(rollup[:total_decisions]).to eq(3)
      expect(rollup[:escalated_decisions]).to eq(2)
    end

    it "groups top rationale categories by complexity level, task_type, and decision kind" do
      escalated_decision(level: "complex", task_type: "code_generation")
      escalated_decision(level: "expert", task_type: "reasoning", tier: "frontier")
      standard_decision(kind: "pinned")

      rollup = service.escalation_rollup
      cats = rollup[:top_rationale_categories]
      expect(cats[:by_complexity_level]).to include("complex" => 1, "expert" => 1)
      expect(cats[:by_task_type]).to include("code_generation" => 1, "reasoning" => 1)
      expect(cats[:by_decision_kind]).to include("escalate" => 2, "pinned" => 1)
    end

    it "computes escalated spend share of total spend" do
      escalated_decision(outcome_trait: :successful) # actual_cost_usd 0.0008
      standard_decision(outcome_trait: :successful)  # actual_cost_usd 0.0008

      rollup = service.escalation_rollup
      expect(rollup[:spend][:total_usd]).to be_within(0.00001).of(0.0016)
      expect(rollup[:spend][:escalated_usd]).to be_within(0.00001).of(0.0008)
      expect(rollup[:spend][:escalated_share_pct]).to be_within(0.01).of(50.0)
    end

    it "embeds the benefit summary and advisory" do
      a = assessment_for
      escalated_decision(assessment: a)
      standard_decision(assessment: assessment_for)

      rollup = service.escalation_rollup
      expect(rollup[:benefit]).to include(:success_rate_delta, :matched_buckets)
      expect(rollup[:advisory]).to include(:recommend_tightening, :status, :threshold)
    end
  end

  # =========================================================================
  # (b2) escalation_benefit_deltas — controlled complexity matching
  # =========================================================================
  describe "#escalation_benefit_deltas" do
    it "returns clean empty state with no decisions" do
      benefit = service.escalation_benefit_deltas

      expect(benefit[:buckets]).to eq([])
      expect(benefit[:summary][:success_rate_delta]).to be_nil
      expect(benefit[:summary][:matched_buckets]).to eq(0)
      expect(benefit[:summary][:avg_latency_delta_by_seam]).to eq({})
      expect(benefit[:advisory][:recommend_tightening]).to be(false)
      expect(benefit[:advisory][:status]).to eq("no_escalations")
    end

    it "compares escalated vs standard cohorts matched on complexity level" do
      # complex bucket: escalated succeeds, standard fails -> positive benefit
      escalated_decision(level: "complex", assessment: assessment_for(level: "complex"), outcome_trait: :successful)
      standard_decision(level: "complex", assessment: assessment_for(level: "complex"), outcome_trait: :failed)

      benefit = service.escalation_benefit_deltas
      bucket = benefit[:buckets].find { |b| b[:complexity_level] == "complex" }

      expect(bucket).to be_present
      expect(bucket[:matched]).to be(true)
      expect(bucket[:escalated][:success_rate]).to eq(100.0)
      expect(bucket[:standard][:success_rate]).to eq(0.0)
      expect(bucket[:deltas][:success_rate]).to eq(100.0)
    end

    it "leaves deltas nil for an unmatched bucket (escalated present, no standard peer)" do
      escalated_decision(level: "expert", task_type: "reasoning",
                         assessment: assessment_for(level: "expert", task_type: "reasoning"), tier: "frontier")

      benefit = service.escalation_benefit_deltas
      bucket = benefit[:buckets].find { |b| b[:complexity_level] == "expert" }
      expect(bucket[:matched]).to be(false)
      expect(bucket[:deltas][:success_rate]).to be_nil
    end

    it "filters by task_type" do
      escalated_decision(task_type: "code_generation", assessment: assessment_for(task_type: "code_generation"))
      escalated_decision(task_type: "reasoning", assessment: assessment_for(task_type: "reasoning"))

      benefit = service.escalation_benefit_deltas(task_type: "reasoning")
      expect(benefit[:buckets].map { |b| b[:task_type] }.uniq).to eq([ "reasoning" ])
    end
  end

  # =========================================================================
  # (b2) latency semantics — segmented by recording seam, never pooled
  # =========================================================================
  # Latency is recorded with different semantics per seam (agent_execution =
  # AgentExecution duration; ralph_iteration = whole-iteration duration), so
  # latency rollups are segmented by the rationale.latency_seam tag while
  # success rate and cost stay pooled.
  describe "latency seam segmentation" do
    it "segments cohort latency and deltas by seam, comparing only shared seams" do
      a = assessment_for
      escalated_decision(assessment: a, seam: "agent_execution", latency_ms: 250)
      escalated_decision(assessment: assessment_for, seam: "ralph_iteration", latency_ms: 60_000)
      standard_decision(assessment: assessment_for, seam: "agent_execution", latency_ms: 500)

      benefit = service.escalation_benefit_deltas
      summary = benefit[:summary]

      # success/cost stay pooled
      expect(summary[:success_rate_delta]).to eq(0.0)
      expect(summary[:avg_cost_delta]).to eq(0.0)
      # latency delta only for the seam present in BOTH cohorts
      expect(summary[:avg_latency_delta_by_seam]).to eq({ "agent_execution" => -250.0 })
      expect(summary).not_to have_key(:avg_latency_delta)

      bucket = benefit[:buckets].first
      expect(bucket[:escalated][:avg_latency_ms_by_seam]).to include("agent_execution" => 250.0)
      expect(bucket[:standard][:avg_latency_ms_by_seam]).to eq({ "agent_execution" => 500.0 })
      expect(bucket[:deltas][:avg_latency_ms_by_seam]).to eq({ "agent_execution" => -250.0 })
    end

    it "buckets untagged latencies under the unknown seam (legacy rows)" do
      escalated_decision(assessment: assessment_for, latency_ms: 300)
      standard_decision(assessment: assessment_for, latency_ms: 100)

      summary = service.escalation_benefit_deltas[:summary]
      expect(summary[:avg_latency_delta_by_seam]).to eq({ "unknown" => 200.0 })
    end

    it "yields no latency deltas when cohorts share no seam" do
      escalated_decision(assessment: assessment_for, seam: "ralph_iteration", latency_ms: 60_000)
      standard_decision(assessment: assessment_for, seam: "agent_execution", latency_ms: 500)

      summary = service.escalation_benefit_deltas[:summary]
      expect(summary[:avg_latency_delta_by_seam]).to eq({})
      # success stays pooled and comparable even without a shared latency seam
      expect(summary[:success_rate_delta]).to eq(0.0)
    end
  end

  # =========================================================================
  # (b3) advisory heuristic — fires and stays silent
  # =========================================================================
  describe "advisory heuristic" do
    it "recommends tightening when escalated cohort shows non-positive benefit at scale" do
      # 12 escalated (succeed) but each standard peer ALSO succeeds -> delta 0 (null benefit)
      12.times do
        escalated_decision(assessment: assessment_for, outcome_trait: :successful)
      end
      6.times do
        standard_decision(assessment: assessment_for, outcome_trait: :successful)
      end

      benefit = service.escalation_benefit_deltas
      expect(benefit[:summary][:escalated_measured]).to be >= 10
      expect(benefit[:summary][:success_rate_delta]).to be <= 0
      expect(benefit[:advisory][:recommend_tightening]).to be(true)
      expect(benefit[:advisory][:status]).to eq("non_positive_benefit")
      expect(benefit[:advisory][:message]).to match(/tighten/i)
    end

    it "stays silent when escalated cohort shows a positive benefit" do
      12.times { escalated_decision(assessment: assessment_for, outcome_trait: :successful) }
      12.times { standard_decision(assessment: assessment_for, outcome_trait: :failed) }

      benefit = service.escalation_benefit_deltas
      expect(benefit[:summary][:success_rate_delta]).to be > 0
      expect(benefit[:advisory][:recommend_tightening]).to be(false)
      expect(benefit[:advisory][:status]).to eq("beneficial")
    end

    it "stays silent (insufficient data) below the decision threshold even at zero benefit" do
      2.times { escalated_decision(assessment: assessment_for, outcome_trait: :successful) }
      2.times { standard_decision(assessment: assessment_for, outcome_trait: :successful) }

      benefit = service.escalation_benefit_deltas
      expect(benefit[:advisory][:recommend_tightening]).to be(false)
      expect(benefit[:advisory][:status]).to eq("insufficient_data")
    end

    it "reports insufficient comparison data when escalations have no standard peer" do
      12.times { escalated_decision(assessment: assessment_for, outcome_trait: :successful) }

      benefit = service.escalation_benefit_deltas
      expect(benefit[:advisory][:recommend_tightening]).to be(false)
      expect(benefit[:advisory][:status]).to eq("insufficient_comparison_data")
    end
  end
end
