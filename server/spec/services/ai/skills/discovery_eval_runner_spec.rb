# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Skills::DiscoveryEvalRunner do
  let!(:account) { create(:account) }

  it "scores every authored eval from every loaded batch and writes nothing" do
    runner = described_class.new(embedder: :lexical, account: account, threshold: 1.0)
    expect { runner.run }.not_to change { [ Ai::Skill.count, Ai::KnowledgeGraphNode.count ] }

    authored = Ai::Skills::CapabilitySeeder.data_sources.sum do |_owner, dir|
      Ai::Skills::CapabilitySeeder.load_entries(dir).sum { |e| e["evals"].size }
    end
    totals = runner.totals
    expect(totals[:evals]).to eq(authored)
    expect(totals[:embedder]).to eq("lexical")
    expect(totals[:hit3]).to be > (totals[:positives] / 2)
    expect(runner.rows.first.to_h.keys).to include(:slug, :task, :expected, :rank, :top)
  end

  it "applies the production cut-off by default" do
    runner = described_class.new(embedder: :lexical, account: account)
    expect(runner.instance_variable_get(:@threshold)).to eq(Ai::SkillGraph::TraversalService::SEED_DISTANCE_THRESHOLD)
  end

  it "refuses to run on a provider that cannot embed (no silent fallback)" do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate_or_nil).and_return(nil)
    expect { described_class.new(embedder: :provider, account: account).run }.to raise_error(Ai::Skills::SkillEmbedder::EmbeddingUnavailable)
  end
end
