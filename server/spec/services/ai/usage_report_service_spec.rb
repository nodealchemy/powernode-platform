# frozen_string_literal: true

require "rails_helper"

# Phase 0 (b): the baseline later prompt changes are measured against.
RSpec.describe Ai::UsageReportService do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  def execution(metrics, method: "complete", created_at: Time.current)
    create(:ai_agent_execution, account: account, agent: agent,
                                input_parameters: { method: method, model: "claude-fable-5" },
                                performance_metrics: metrics, created_at: created_at)
  end

  before do
    execution({ model: "claude-fable-5", prompt_tokens: 100, cached_tokens: 80, cache_creation_tokens: 20,
                completion_tokens: 10, finish_reason: "end_turn" })
    execution({ model: "claude-fable-5", prompt_tokens: 50, cached_tokens: 0, cache_creation_tokens: 0,
                completion_tokens: 900, finish_reason: "max_tokens" })
    execution({ model: "claude-fable-5", prompt_tokens: 5, refused: true, finish_reason: "refusal" },
              method: "complete_structured")
    execution({ model: "claude-fable-5", prompt_tokens: 999 }, created_at: 30.days.ago)
  end

  it "groups by model and call site, summing tokens and counting stops and refusals" do
    rows = described_class.new(days: 7, account: account).rows
    site = "#{agent.slug} #complete"

    expect(rows.first).to include(model: "claude-fable-5", call_site: site, calls: 2, input: 150, cache_read: 80,
                                  cache_creation: 20, output: 910, max_tokens_stops: 1, refusals: 0)
    expect(rows.last).to include(call_site: "#{agent.slug} #complete_structured", calls: 1, refusals: 1)
  end

  it "leaves executions outside the window out, and totals the rest" do
    totals = described_class.new(days: 7, account: account).totals

    expect(totals[:calls]).to eq(3)
    expect(totals[:input]).to eq(155)
  end

  it "counts executions from before the capture as zero cache writes" do
    execution({ model: "legacy-model", prompt_tokens: 10 })
    row = described_class.new(days: 7, account: account).rows.find { |r| r[:model] == "legacy-model" }

    expect(row).to include(cache_creation: 0, max_tokens_stops: 0)
  end

  it "rejects a non-positive window" do
    expect { described_class.new(days: 0) }.to raise_error(ArgumentError)
  end
end
